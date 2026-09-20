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

local function cell(entry)
  if not entry then
    return ''
  end
  local tools = {}
  for _, t in ipairs(entry.tools) do
    tools[#tools + 1] = t
  end
  if #tools == 0 then
    return string.format('<span style="color:#d33">✗</span> <small>(%d)</small>', entry.files)
  end
  return table.concat(tools, ', ')
end

function p.table()
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
  local head = { '! 저장소' }
  for _, k in ipairs(kinds) do
    head[#head + 1] = '!! ' .. k[2]
  end
  local out = { '{| class="wikitable"', table.concat(head, ' ') }
  for _, r in ipairs(repos) do
    local row = { string.format('| [https://github.com/femiwiki/%s %s]', r.name, r.name) }
    for _, k in ipairs(kinds) do
      row[#row + 1] = '| ' .. cell(r.kinds[k[1]])
    end
    out[#out + 1] = '|-\n' .. table.concat(row, '\n')
  end
  out[#out + 1] = '|}'
  return string.format('%s 기준.\n%s', data.generated, table.concat(out, '\n'))
end

return p
