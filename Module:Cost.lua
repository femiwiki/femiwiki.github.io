local p = {}

local function commas(s)
  local sign, int, frac = tostring(s):match('^(%-?)(%d+)(%.?%d*)$')
  int = int:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
  return sign .. int .. frac
end

local function usd(x)
  x = tonumber(x)
  if math.abs(x) < 0.005 then
    x = 0
  end
  return commas(string.format('%.2f', x))
end

local function load(name)
  return mw.loadJsonData('Module:비용/' .. name)
end

local function list(t)
  local out = {}
  for _, v in ipairs(t) do
    out[#out + 1] = v
  end
  return out
end

local function amountTag(x)
  return string.format('<span class="cost-amount">%s USD</span>', usd(x))
end

-- Won for the month: as billed, or the dollar amount at the ECB rate of the invoice date.
local function won(e)
  if e.currency == 'KRW' then
    return e.billed, false
  elseif e.currency == 'USD' and e.rate then
    return e.billed * tonumber(e.rate), true
  end
  return nil
end

local function wonCell(amount, estimated)
  if not amount then
    return '| -'
  end
  local text = commas(string.format('%d', amount))
  return string.format('| data-sort-value="%d" | %s%s', amount, estimated and '≈ ' or '', text)
end

local function billedText(e)
  if not e.currency then
    return '-'
  end
  local amount = e.currency == 'USD' and usd(e.billed) or commas(string.format('%d', e.billed))
  return amount .. ' ' .. e.currency
end

-- The month's services with usage, credits and net, from the console's bill when it was
-- captured, else from Cost Explorer grouped by service and record type.
local function services(m)
  local ok, bill = pcall(load, m .. '/bill.json')
  if ok then
    local rows = {}
    for _, s in ipairs(bill.services) do
      local usage = 0
      for _, r in ipairs(s.regions) do
        for _, g in ipairs(r.groups) do
          for _, i in ipairs(g.items) do
            if i.type ~= 'Credit' then
              usage = usage + i.amount
            end
          end
        end
      end
      rows[#rows + 1] = { name = s.name, usage = usage, net = s.amount }
    end
    return rows, bill, '청구서'
  end
  local found, cost = pcall(load, m .. '/cost.json')
  if not found then
    return nil
  end
  local by = {}
  local rows = {}
  for _, g in ipairs(cost.ResultsByTime[1].Groups) do
    local name, kind = g.Keys[1], g.Keys[2]
    local amount = tonumber(g.Metrics.UnblendedCost.Amount)
    if kind ~= 'Tax' then
      if not by[name] then
        by[name] = { name = name, usage = 0, net = 0 }
        rows[#rows + 1] = by[name]
      end
      by[name].net = by[name].net + amount
      if kind ~= 'Credit' and kind ~= 'Refund' then
        by[name].usage = by[name].usage + amount
      end
    end
  end
  return rows, nil, 'Cost Explorer'
end

function p.status()
  local ok, entries = pcall(load, 'months.json')
  if not ok then
    return '아직 수집된 달이 없습니다.'
  end
  local months = list(entries)

  local years, order = {}, {}
  local rows = {
    '{| class="wikitable sortable"',
    '! 월 !! 사용 !! 크레딧 !! 세금 !! 합계 (USD) !! 청구 !! 환율 !! 원화 (KRW)',
  }
  for i = #months, 1, -1 do
    local e = months[i]
    local usage, total = e.usage or e.gross, e.total or e.net
    local krw, estimated = won(e)
    rows[#rows + 1] = string.format(
      '|-\n| [[비용/%s|%s]] || %s || %s || %s || %s || %s || %s\n%s',
      e.month,
      e.month,
      usage and usd(usage) or '-',
      e.credits and usd(-e.credits) or '-',
      e.tax and usd(e.tax) or '-',
      total and usd(total) or '-',
      billedText(e),
      e.rate and ((e.rateEstimated and '≈ ' or '') .. e.rate:sub(1, 7)) or '-',
      wonCell(krw, estimated)
    )
    local y = e.month:sub(1, 4)
    if not years[y] then
      years[y] = { usage = 0, credits = 0, krw = 0, estimated = false }
      order[#order + 1] = y
    end
    years[y].usage = years[y].usage + (usage or 0)
    years[y].credits = years[y].credits + (e.credits or 0)
    if krw then
      years[y].krw = years[y].krw + krw
      years[y].estimated = years[y].estimated or estimated
    end
  end
  rows[#rows + 1] = '|}'

  local out = {
    '== 연도별 ==',
    '{| class="wikitable sortable"',
    '! 연도 !! 사용 (USD) !! 크레딧 (USD) !! 청구 (KRW)',
  }
  for _, y in ipairs(order) do
    out[#out + 1] = string.format(
      '|-\n| %s || %s || %s\n%s',
      y,
      usd(years[y].usage),
      usd(-years[y].credits),
      wonCell(years[y].krw, years[y].estimated)
    )
  end
  out[#out + 1] = '|}'
  out[#out + 1] = ''
  out[#out + 1] = '== 월별 =='
  for _, r in ipairs(rows) do
    out[#out + 1] = r
  end

  local latest = months[#months].month
  local found, snapshot = pcall(load, latest .. '/credits.json')
  if found then
    local credits = list(snapshot)
    table.sort(credits, function(a, b)
      return (a.startDate or '') < (b.startDate or '')
    end)
    out[#out + 1] = ''
    out[#out + 1] = '== ' .. latest .. ' 마감 크레딧 =='
    out[#out + 1] = '{| class="wikitable"'
    out[#out + 1] = '! 이름 !! 초기 (USD) !! 마감 잔액 (USD) !! 시작 !! 종료 !! 소진'
    for _, c in ipairs(credits) do
      out[#out + 1] = string.format(
        '|-\n| %s || %s || %s || %s || %s || %s',
        c.description or '',
        usd(c.initialAmount.currencyAmount),
        usd(c.closingAmount),
        (c.startDate or ''):sub(1, 10),
        (c.endDate or ''):sub(1, 10),
        c.exhaustDate and c.exhaustDate:sub(1, 10) or '-'
      )
    end
    out[#out + 1] = '|}'
  end
  return '\n' .. table.concat(out, '\n')
end

function p.month(frame)
  local m = frame.args[1]
  local out = {}
  local inv = load(m .. '/invoice.json').InvoiceSummaries[1]
  local billed = inv
      and billedText({
        currency = inv.PaymentCurrencyAmount.CurrencyCode,
        billed = inv.PaymentCurrencyAmount.TotalAmount,
      })
    or '-'

  local rows, bill, source = services(m)
  if rows then
    table.sort(rows, function(a, b)
      return a.usage > b.usage
    end)
    local usage, net = 0, 0
    for _, r in ipairs(rows) do
      usage, net = usage + r.usage, net + r.net
    end
    out[#out + 1] = string.format(
      '%s AWS 사용 %s USD, 크레딧 %s USD, 세전 %s USD. 청구 %s. 서비스별 금액은 %s 기준입니다.',
      m,
      usd(usage),
      usd(usage - net),
      usd(net),
      billed,
      source
    )
    out[#out + 1] = ''
    out[#out + 1] = '{| class="wikitable sortable"'
    out[#out + 1] = '! 서비스 !! 사용 (USD) !! 크레딧 (USD) !! 순액 (USD)'
    for _, r in ipairs(rows) do
      out[#out + 1] =
        string.format('|-\n| %s || %s || %s || %s', r.name, usd(r.usage), usd(r.usage - r.net), usd(r.net))
    end
    out[#out + 1] = '|}'
  else
    out[#out + 1] = string.format('%s AWS 청구 %s.', m, billed)
  end

  if bill then
    out[#out + 1] = ''
    out[#out + 1] = '=== 항목별 ==='
    out[#out + 1] = frame:extensionTag('templatestyles', '', { src = 'Cost/styles.css' })
    local function node(name, amount, inner)
      local summary = frame:extensionTag('summary', name .. amountTag(amount))
      return frame:extensionTag('details', summary .. '\n' .. inner)
    end
    local tree = {}
    for _, s in ipairs(bill.services) do
      local regions = {}
      for _, r in ipairs(s.regions) do
        local groups = {}
        for _, g in ipairs(r.groups) do
          local lines = { '{| class="wikitable"', '! 항목 !! 사용량 !! 금액 (USD)' }
          for _, i in ipairs(g.items) do
            local usage = ''
            if i.usage and i.usage ~= 0 then
              usage = commas(string.format('%.3f', i.usage)):gsub('%.?0+$', '') .. ' ' .. (i.unit or '')
            end
            lines[#lines + 1] = string.format('|-\n| %s\n| %s\n| %s', i.description, usage, usd(i.amount))
          end
          lines[#lines + 1] = '|}'
          groups[#groups + 1] = node(g.name or '기타', g.amount, table.concat(lines, '\n'))
        end
        regions[#regions + 1] = node(r.name, r.amount, table.concat(groups, '\n'))
      end
      tree[#tree + 1] = node(s.name, s.amount, table.concat(regions, '\n'))
    end
    out[#out + 1] = '<div class="cost-tree">\n' .. table.concat(tree, '\n') .. '\n</div>'
  end

  if mw.title.new('File:' .. m .. '.pdf').exists then
    out[#out + 1] = ''
    out[#out + 1] = string.format('[[Media:%s.pdf|청구서 (PDF)]]', m)
  end
  return '\n' .. table.concat(out, '\n')
end

return p
