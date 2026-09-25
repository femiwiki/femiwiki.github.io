local p = {}

local kinds = {
  { 'tf', 'Terraform' },
  { 'go', 'Go' },
  { 'py', 'Python' },
  { 'php', 'PHP' },
  { 'js', 'JS' },
  { 'css', 'CSS' },
  { 'json', 'JSON' },
  { 'yaml', 'YAML' },
  { 'actions', 'Actions' },
  { 'md', 'Markdown' },
  { 'sh', 'Shell' },
  { 'lua', 'Lua' },
  { 'dockerfile', 'Dockerfile' },
  { 'toml', 'TOML' },
  { 'caddyfile', 'Caddyfile' },
}

local function chip(text, state)
  return string.format('<span class="lint-chip%s">%s</span>', state and ' lint-chip-' .. state or '', text)
end

local function chips(list)
  return '<div class="lint-chips">' .. table.concat(list) .. '</div>'
end

-- Tool names in the inventory's order, the required ones in bold, plus whether
-- any of them is required.
local function tools(entry)
  local names = {}
  local required = false
  for _, t in ipairs(entry.tools) do
    names[#names + 1] = t.required and '<b>' .. t.name .. '</b>' or t.name
    required = required or t.required
  end
  return names, required
end

local function repoLink(name)
  return string.format('[https://github.com/femiwiki/%s %s]', name, name)
end

local function count(set)
  local n = 0
  for _ in pairs(set) do
    n = n + 1
  end
  return n
end

local function gapSection(title, rows)
  if #rows == 0 then
    return {}
  end
  return {
    '== ' .. title .. ' ==',
    '{| class="wikitable lint-table"',
    '! 종류 !! 저장소 (파일 수)',
    table.concat(rows, '\n'),
    '|}',
    '',
  }
end

function p.status(frame)
  local ok, data = pcall(mw.loadJsonData, 'Module:린트/inventory.json')
  if not ok then
    return '아직 수집된 결과가 없습니다.'
  end
  local repos = {}
  for _, r in ipairs(data.repos) do
    repos[#repos + 1] = r
  end
  table.sort(repos, function(a, b)
    return a.name:lower() < b.name:lower()
  end)

  local unchecked, optional = {}, {}
  local uncheckedRepos, optionalRepos = {}, {}
  for _, k in ipairs(kinds) do
    local bad, warn = {}, {}
    for _, r in ipairs(repos) do
      local entry = r.kinds[k[1]]
      if entry then
        local names, required = tools(entry)
        if #names == 0 then
          bad[#bad + 1] = chip(string.format('%s (%d)', repoLink(r.name), entry.files), 'bad')
          uncheckedRepos[r.name] = true
        elseif not required then
          warn[#warn + 1] = chip(string.format('%s (%d)', repoLink(r.name), entry.files), 'warn')
          optionalRepos[r.name] = true
        end
      end
    end
    if #bad > 0 then
      unchecked[#unchecked + 1] = string.format('|-\n| %s\n| %s', k[2], chips(bad))
    end
    if #warn > 0 then
      optional[#optional + 1] = string.format('|-\n| %s\n| %s', k[2], chips(warn))
    end
  end

  local out = {
    frame:extensionTag('templatestyles', '', { src = 'Lint/styles.css' }),
    string.format(
      '%s 기준, 저장소 %d개 중 %d개에 검사되지 않는 파일이 있고, %d개에 필수가 아닌 검사만 받는 파일이 있습니다.',
      data.generated,
      #repos,
      count(uncheckedRepos),
      count(optionalRepos)
    ),
    '',
  }
  for _, line in ipairs(gapSection('검사되지 않는 파일', unchecked)) do
    out[#out + 1] = line
  end
  for _, line in ipairs(gapSection('필수가 아닌 검사만 받는 파일', optional)) do
    out[#out + 1] = line
  end
  out[#out + 1] = '== 종류별 도구 =='
  out[#out + 1] = '{| class="wikitable lint-table"'
  out[#out + 1] = '! 종류 !! 도구 (저장소 수)'
  for _, k in ipairs(kinds) do
    local uses, names = {}, {}
    for _, r in ipairs(repos) do
      local entry = r.kinds[k[1]]
      for _, t in ipairs(entry and entry.tools or {}) do
        if not uses[t.name] then
          uses[t.name] = 0
          names[#names + 1] = t.name
        end
        uses[t.name] = uses[t.name] + 1
      end
    end
    if #names > 0 then
      table.sort(names, function(a, b)
        if uses[a] ~= uses[b] then
          return uses[a] > uses[b]
        end
        return a < b
      end)
      local list = {}
      for _, name in ipairs(names) do
        list[#list + 1] = chip(string.format('%s (%d)', name, uses[name]))
      end
      out[#out + 1] = string.format('|-\n| %s\n| %s', k[2], chips(list))
    end
  end
  out[#out + 1] = '|}'
  out[#out + 1] = ''
  out[#out + 1] = '== 저장소별 =='
  out[#out + 1] = '{| class="wikitable lint-table"'
  out[#out + 1] = '! 저장소 !! 파일 종류와 검사하는 도구'
  for _, r in ipairs(repos) do
    local list = {}
    for _, k in ipairs(kinds) do
      local entry = r.kinds[k[1]]
      if entry then
        local names, required = tools(entry)
        if #names == 0 then
          list[#list + 1] = chip(string.format('%s ✗ (%d)', k[2], entry.files), 'bad')
        else
          list[#list + 1] =
            chip(string.format('%s: %s', k[2], table.concat(names, ', ')), not required and 'warn' or nil)
        end
      end
    end
    out[#out + 1] = string.format('|-\n| %s\n| %s', repoLink(r.name), chips(list))
  end
  out[#out + 1] = '|}'
  return table.concat(out, '\n')
end

return p
