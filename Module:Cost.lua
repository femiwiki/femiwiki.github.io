local p = {}

local function commas(s)
  local int, frac = tostring(s):match('^(%-?%d+)(%.?%d*)$')
  int = int:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
  return int .. frac
end

local function usd(x)
  return commas(string.format('%.2f', tonumber(x)))
end

local function load(name)
  return mw.loadJsonData('Module:비용/' .. name)
end

local function month(m)
  local gross, net, groups
  local ok, cost = pcall(load, m .. '/cost.json')
  if ok then
    groups = cost.ResultsByTime[1].Groups
    gross, net = 0, 0
    for _, g in ipairs(groups) do
      gross = gross + tonumber(g.Metrics.UnblendedCost.Amount)
      net = net + tonumber(g.Metrics.NetUnblendedCost.Amount)
    end
  end
  local billed, rate = '-', '-'
  local inv = load(m .. '/invoice.json').InvoiceSummaries[1]
  if inv then
    local pay = inv.PaymentCurrencyAmount
    billed = commas(pay.TotalAmount) .. ' ' .. pay.CurrencyCode
    if pay.CurrencyExchangeDetails then
      rate = pay.CurrencyExchangeDetails.Rate:sub(1, 7)
    end
  end
  return gross, net, billed, rate, groups
end

local function billedText(entry)
  if not entry.currency then
    return '-'
  end
  local amount = entry.currency == 'USD' and usd(entry.billed) or commas(string.format('%d', entry.billed))
  return amount .. ' ' .. entry.currency
end

function p.status()
  local ok, list = pcall(load, 'months.json')
  if not ok then
    return '아직 수집된 달이 없습니다.'
  end
  local months = {}
  for _, e in ipairs(list) do
    if type(e) == 'string' then
      -- months.json from before it carried totals: one name per month, totals in the month's own files
      local gross, net, billed, rate = month(e)
      e = { month = e, gross = gross, net = net, text = billed, rate = rate }
    end
    months[#months + 1] = e
  end

  local years, order = {}, {}
  local rows = { '{| class="wikitable"', '! 월 !! 총사용 (USD) !! 순지출 (USD) !! 청구 !! 환율' }
  for i = #months, 1, -1 do
    local e = months[i]
    rows[#rows + 1] = string.format(
      '|-\n| [[비용/%s|%s]] || %s || %s || %s || %s',
      e.month,
      e.month,
      e.gross and usd(e.gross) or '-',
      e.net and usd(e.net) or '-',
      e.text or billedText(e),
      e.rate and e.rate:sub(1, 7) or '-'
    )
    local y = e.month:sub(1, 4)
    if not years[y] then
      years[y] = { USD = 0, KRW = 0 }
      order[#order + 1] = y
    end
    if e.currency then
      years[y][e.currency] = (years[y][e.currency] or 0) + e.billed
    end
  end
  rows[#rows + 1] = '|}'

  local out = { '== 연도별 ==', '{| class="wikitable"', '! 연도 !! 청구 (USD) !! 청구 (KRW)' }
  for _, y in ipairs(order) do
    out[#out + 1] = string.format(
      '|-\n| %s || %s || %s',
      y,
      years[y].USD > 0 and usd(years[y].USD) or '',
      years[y].KRW > 0 and commas(string.format('%d', years[y].KRW)) or ''
    )
  end
  out[#out + 1] = '|}'
  out[#out + 1] = ''
  out[#out + 1] = '== 월별 =='
  for _, e in ipairs(months) do
    if e.gross then
      out[#out + 1] = '서비스별 내역은 ' .. e.month .. '부터 있습니다.'
      break
    end
  end
  for _, r in ipairs(rows) do
    out[#out + 1] = r
  end

  local latest = months[#months].month
  local found, snapshot = pcall(load, latest .. '/credits.json')
  if found then
    local credits = {}
    for _, c in ipairs(snapshot) do
      credits[#credits + 1] = c
    end
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
  local gross, net, billed, rate, groups = month(m)
  local out = {}
  if groups then
    local rows = {}
    for _, g in ipairs(groups) do
      rows[#rows + 1] = g
    end
    table.sort(rows, function(a, b)
      return tonumber(a.Metrics.UnblendedCost.Amount) > tonumber(b.Metrics.UnblendedCost.Amount)
    end)
    out[#out + 1] = string.format(
      '%s 서비스별 AWS 요금입니다. 총사용 %s USD, 순지출 %s USD, 청구 %s (환율 %s).',
      m,
      usd(gross),
      usd(net),
      billed,
      rate
    )
    out[#out + 1] = ''
    out[#out + 1] = '{| class="wikitable sortable"'
    out[#out + 1] = '! 서비스 !! 총사용 (USD) !! 순지출 (USD)'
    for _, g in ipairs(rows) do
      out[#out + 1] = string.format(
        '|-\n| %s || %s || %s',
        g.Keys[1],
        usd(g.Metrics.UnblendedCost.Amount),
        usd(g.Metrics.NetUnblendedCost.Amount)
      )
    end
    out[#out + 1] = '|}'
  else
    out[#out + 1] = string.format('%s AWS 청구 %s.', m, billed)
  end
  if mw.title.new('File:' .. m .. '.pdf').exists then
    out[#out + 1] = ''
    out[#out + 1] = string.format('[[Media:%s.pdf|청구서 (PDF)]]', m)
  end
  return '\n' .. table.concat(out, '\n')
end

return p
