local p = {}

local site = '페미위키:대문'

local function load(name)
  return mw.loadJsonData('Module:가용성/' .. name)
end

local function list(t)
  local out = {}
  for _, v in ipairs(t) do
    out[#out + 1] = v
  end
  return out
end

-- Colour class for a fraction of probes that passed.
local function grade(x)
  if x == nil then
    return 'av-none'
  elseif x >= 0.99999 then
    return 'av-a'
  elseif x >= 0.999 then
    return 'av-b'
  elseif x >= 0.99 then
    return 'av-c'
  elseif x >= 0.95 then
    return 'av-d'
  end
  return 'av-e'
end

-- 100, 99.9, 99.63, 87.93: as many decimals as it takes to be honest, at most two.
local function percent(x)
  if x == nil then
    return '-'
  end
  local s = string.format('%.2f', x * 100):gsub('0+$', ''):gsub('%.$', '')
  return s
end

local function mean(values)
  local sum, n = 0, 0
  for _, v in ipairs(values) do
    if v ~= nil then
      sum, n = sum + v, n + 1
    end
  end
  if n == 0 then
    return nil
  end
  return sum / n
end

local function daysIn(year, month)
  return tonumber(os.date('%d', os.time({ year = year, month = month + 1, day = 0 })))
end

-- 2026-09 -> 가용성/2026년 9월, the page people write the month's story on.
local function pageOf(m)
  return string.format('가용성/%s년 %d월', m:sub(1, 4), tonumber(m:sub(6, 7)))
end

local function styles(frame)
  return frame:extensionTag('templatestyles', '', { src = 'Availability/styles.css' })
end

-- Years by months, one table per check, from the monthly summaries.
function p.status(frame)
  local ok, entries = pcall(load, 'months.json')
  if not ok then
    return '아직 수집된 달이 없습니다.'
  end
  local months = list(entries)
  local names = { site }
  for name in pairs(months[#months].checks) do
    if name ~= site then
      names[#names + 1] = name
    end
  end

  local out = { styles(frame) }
  for _, name in ipairs(names) do
    local byMonth, years, order = {}, {}, {}
    for _, e in ipairs(months) do
      local y = e.month:sub(1, 4)
      if not years[y] then
        years[y] = true
        order[#order + 1] = y
      end
      byMonth[e.month] = e.checks[name]
    end
    table.sort(order, function(a, b)
      return a > b
    end)
    out[#out + 1] = '== ' .. name .. ' =='
    out[#out + 1] = '{| class="wikitable av-grid"'
    out[#out + 1] = '! 연도 !! 1 !! 2 !! 3 !! 4 !! 5 !! 6 !! 7 !! 8 !! 9 !! 10 !! 11 !! 12 !! 연간'
    for _, y in ipairs(order) do
      local cells, values = { '| ' .. y }, {}
      for m = 1, 12 do
        local key = string.format('%s-%02d', y, m)
        local e = byMonth[key]
        if e then
          values[#values + 1] = e.uptime
          cells[#cells + 1] = string.format('| class="%s" | [[%s|%s]]', grade(e.uptime), pageOf(key), percent(e.uptime))
        else
          cells[#cells + 1] = '| class="av-none" |'
        end
      end
      local year = mean(values)
      cells[#cells + 1] = string.format('| class="%s" | %s', grade(year), percent(year))
      out[#out + 1] = '|-\n' .. table.concat(cells, '\n')
    end
    out[#out + 1] = '|}'
  end
  return '\n' .. table.concat(out, '\n')
end

-- Days by hours for one month, one table per check.
function p.month(frame)
  local m = frame.args[1]
  local ok, data = pcall(load, m .. '.json')
  if not ok then
    return m .. '에는 수집된 자료가 없습니다.'
  end
  local year, month = tonumber(m:sub(1, 4)), tonumber(m:sub(6, 7))
  local days = daysIn(year, month)
  local names = { site }
  for name in pairs(data.checks) do
    if name ~= site then
      names[#names + 1] = name
    end
  end

  local out = { styles(frame) }
  for _, name in ipairs(names) do
    local hours = list(data.checks[name])
    local monthly = mean(hours)
    out[#out + 1] = string.format('== %s ==', name)
    out[#out + 1] = string.format('%s 가용성 %s%%.', m, percent(monthly))
    out[#out + 1] = '{| class="wikitable av-grid"'
    out[#out + 1] = '! 날짜 !! 가용성 !! 0시부터 23시까지'
    for d = 1, days do
      local slice, boxes = {}, {}
      for h = 0, 23 do
        local v = hours[(d - 1) * 24 + h + 1]
        slice[#slice + 1] = v
        boxes[#boxes + 1] = string.format('<span class="%s" title="%02d시 %s%%"></span>', grade(v), h, percent(v))
      end
      local day = mean(slice)
      out[#out + 1] = string.format(
        '|-\n| class="av-day" | %s-%02d\n| class="%s" | %s\n| <span class="av-hours">%s</span>',
        m,
        d,
        grade(day),
        percent(day),
        table.concat(boxes)
      )
    end
    out[#out + 1] = '|}'

    -- Stretches of hours in which probes failed, for the story below to refer to.
    local runs, run = {}, nil
    for i, v in ipairs(hours) do
      if v ~= nil and v < 0.99999 then
        if run and run.last == i - 1 then
          run.last, run.sum, run.n = i, run.sum + v, run.n + 1
          run.worst = math.min(run.worst, v)
        else
          run = { first = i, last = i, sum = v, n = 1, worst = v }
          runs[#runs + 1] = run
        end
      end
    end
    local notable = {}
    for _, r in ipairs(runs) do
      if r.worst < 0.99 or r.n >= 2 then
        notable[#notable + 1] = r
      end
    end
    if #notable > 0 then
      out[#out + 1] = ''
      out[#out + 1] =
        '실패한 요청이 있었던 시간대입니다. 값은 그 동안 성공한 요청의 비율이고, 괄호는 가장 나빴던 한 시간입니다.'
      for _, r in ipairs(notable) do
        local d1, h1 = math.floor((r.first - 1) / 24) + 1, (r.first - 1) % 24
        local d2, h2 = math.floor((r.last - 1) / 24) + 1, (r.last - 1) % 24
        out[#out + 1] = string.format(
          '* %s-%02d %02d시부터 %s-%02d %02d시까지, %d시간, %s%% (%s%%)',
          m,
          d1,
          h1,
          m,
          d2,
          h2 + 1,
          r.n,
          percent(r.sum / r.n),
          percent(r.worst)
        )
      end
    end
  end
  return '\n' .. table.concat(out, '\n')
end

return p
