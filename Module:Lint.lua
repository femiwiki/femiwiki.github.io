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
  { 'md', 'Markdown' },
  { 'sh', 'Shell' },
  { 'lua', 'Lua' },
  { 'dockerfile', 'Dockerfile' },
  { 'toml', 'TOML' },
}

local function chip(text, bad)
  return string.format('<span class="lint-chip%s">%s</span>', bad and ' lint-chip-bad' or '', text)
end

local function chips(list)
  return '<div class="lint-chips">' .. table.concat(list) .. '</div>'
end

local function tools(entry)
  local names = {}
  for _, t in ipairs(entry.tools) do
    names[#names + 1] = t
  end
  return names
end

local function repoLink(name)
  return string.format('[https://github.com/femiwiki/%s %s]', name, name)
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

  local gaps = {}
  local gapRepos = {}
  for _, k in ipairs(kinds) do
    local list = {}
    for _, r in ipairs(repos) do
      local entry = r.kinds[k[1]]
      if entry and #tools(entry) == 0 then
        list[#list + 1] = chip(string.format('%s (%d)', repoLink(r.name), entry.files), true)
        gapRepos[r.name] = true
      end
    end
    if #list > 0 then
      gaps[#gaps + 1] = string.format('|-\n| %s\n| %s', k[2], chips(list))
    end
  end
  local n = 0
  for _ in pairs(gapRepos) do
    n = n + 1
  end

  local out = {
    frame:extensionTag('templatestyles', '', { src = 'Lint/styles.css' }),
    string.format(
      '%s 기준, 저장소 %d개 중 %d개에 검사되지 않는 파일이 있습니다.',
      data.generated,
      #repos,
      n
    ),
    '',
    '== 검사되지 않는 파일 ==',
    '{| class="wikitable lint-table"',
    '! 종류 !! 저장소 (파일 수)',
    table.concat(gaps, '\n'),
    '|}',
    '',
    '== 저장소별 ==',
    '{| class="wikitable lint-table"',
    '! 저장소 !! 파일 종류와 검사하는 도구',
  }
  for _, r in ipairs(repos) do
    local list = {}
    for _, k in ipairs(kinds) do
      local entry = r.kinds[k[1]]
      if entry then
        local names = tools(entry)
        if #names == 0 then
          list[#list + 1] = chip(string.format('%s ✗ (%d)', k[2], entry.files), true)
        else
          list[#list + 1] = chip(string.format('%s: %s', k[2], table.concat(names, ', ')))
        end
      end
    end
    out[#out + 1] = string.format('|-\n| %s\n| %s', repoLink(r.name), chips(list))
  end
  out[#out + 1] = '|}'
  return table.concat(out, '\n')
end

return p
