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
  local groups = load(m .. '/cost.json').ResultsByTime[1].Groups
  local gross, net = 0, 0
  for _, g in ipairs(groups) do
    gross = gross + tonumber(g.Metrics.UnblendedCost.Amount)
    net = net + tonumber(g.Metrics.NetUnblendedCost.Amount)
  end
  local krw, rate = '-', '-'
  local inv = load(m .. '/invoice.json').InvoiceSummaries[1]
  if inv then
    local pay = inv.PaymentCurrencyAmount
    krw = commas(pay.TotalAmount)
    if pay.CurrencyExchangeDetails then
      rate = pay.CurrencyExchangeDetails.Rate:sub(1, 7)
    end
  end
  return gross, net, krw, rate, groups
end

function p.status()
  local ok, list = pcall(load, 'months.json')
  if not ok then
    return '아직 수집된 달이 없습니다.'
  end
  local months = {}
  for _, m in ipairs(list) do
    months[#months + 1] = m
  end
  local out = { '{| class="wikitable"', '! 월 !! 총사용 (USD) !! 순지출 (USD) !! 청구 (KRW) !! 환율' }
  for i = #months, 1, -1 do
    local m = months[i]
    local gross, net, krw, rate = month(m)
    out[#out + 1] = string.format('|-\n| [[비용/%s|%s]] || %s || %s || %s || %s', m, m, usd(gross), usd(net), krw, rate)
  end
  out[#out + 1] = '|}'

  local latest = months[#months]
  local ok, snapshot = pcall(load, latest .. '/credits.json')
  if ok then
    local credits = {}
    for _, c in ipairs(snapshot) do
      credits[#credits + 1] = c
    end
    table.sort(credits, function(a, b) return (a.startDate or '') < (b.startDate or '') end)
    out[#out + 1] = ''
    out[#out + 1] = '== ' .. latest .. ' 마감 크레딧 =='
    out[#out + 1] = '{| class="wikitable"'
    out[#out + 1] = '! 이름 !! 초기 (USD) !! 마감 잔액 (USD) !! 시작 !! 종료 !! 소진'
    for _, c in ipairs(credits) do
      out[#out + 1] = string.format('|-\n| %s || %s || %s || %s || %s || %s',
        c.description or '', usd(c.initialAmount.currencyAmount), usd(c.closingAmount),
        (c.startDate or ''):sub(1, 10), (c.endDate or ''):sub(1, 10), c.exhaustDate and c.exhaustDate:sub(1, 10) or '-')
    end
    out[#out + 1] = '|}'
  end
  return '\n' .. table.concat(out, '\n')
end

function p.month(frame)
  local m = frame.args[1]
  local gross, net, krw, rate, groups = month(m)
  local rows = {}
  for _, g in ipairs(groups) do
    rows[#rows + 1] = g
  end
  table.sort(rows, function(a, b) return tonumber(a.Metrics.UnblendedCost.Amount) > tonumber(b.Metrics.UnblendedCost.Amount) end)
  local out = {
    string.format('%s 서비스별 AWS 요금입니다. 총사용 %s USD, 순지출 %s USD, 청구 %s KRW (환율 %s).', m, usd(gross), usd(net), krw, rate),
    '', '{| class="wikitable sortable"', '! 서비스 !! 총사용 (USD) !! 순지출 (USD)' }
  for _, g in ipairs(rows) do
    out[#out + 1] = string.format('|-\n| %s || %s || %s', g.Keys[1], usd(g.Metrics.UnblendedCost.Amount), usd(g.Metrics.NetUnblendedCost.Amount))
  end
  out[#out + 1] = '|}'
  out[#out + 1] = ''
  if mw.title.new('File:' .. m .. '.pdf').exists then
    out[#out + 1] = string.format('[[Media:%s.pdf|청구서 (PDF)]] · [[비용/현황|현황으로]]', m)
  else
    out[#out + 1] = '[[비용/현황|현황으로]]'
  end
  return '\n' .. table.concat(out, '\n')
end

return p
