
-- Custom amsthm environments extension for Quarto
-- Allows defining custom theorem-like environments using crossref metadata

local custom_amsthm_envs = {}
local amsthm_counters = {}
local current_counters = {}

-- Function to process metadata and extract custom amsthm environments
function process_custom_amsthm(meta)
  if meta["custom-amsthm"] then
    for _, custom in ipairs(meta["custom-amsthm"]) do
      local key = pandoc.utils.stringify(custom.key)
      local name = pandoc.utils.stringify(custom.name or key)
      local reference_prefix = pandoc.utils.stringify(custom["reference-prefix"] or name)
      local latex_name = pandoc.utils.stringify(custom["latex-name"] or name:lower())
      local numbered = custom.numbered == nil or custom.numbered -- default to true
      -- Get numbering style: "section" (default) or "global"
      local numbering_style = pandoc.utils.stringify(custom["numbering-style"] or "section")
      
      custom_amsthm_envs[key] = {
        name = name,
        reference_prefix = reference_prefix,
        latex_name = latex_name,
        numbered = numbered,
        numbering_style = numbering_style
      }
      
      -- Initialize counter
      amsthm_counters[key] = 0
      current_counters[key] = {}
    end
  end
end

-- Function to generate LaTeX headers for custom environments
function generate_latex_headers()
  local headers = {}
  
  for key, env in pairs(custom_amsthm_envs) do
    if env.numbered then
      if env.numbering_style == "section" then
        -- Section-based numbering
        table.insert(headers, "\\newtheorem{" .. env.latex_name .. "}{" .. env.name .. "}[section]")
      else
        -- Global numbering 
        table.insert(headers, "\\newtheorem{" .. env.latex_name .. "}{" .. env.name .. "}")
      end
    else
      table.insert(headers, "\\newtheorem*{" .. env.latex_name .. "}{" .. env.name .. "}")
    end
  end
  
  if #headers > 0 then
    return "\\usepackage{amsthm}\n" .. table.concat(headers, "\n")
  else
    return ""
  end
end

-- Function to handle custom amsthm divs
function handle_amsthm_div(div)
  local id = div.identifier
  if id == "" then
    return div
  end
  
  -- Check if this div has an ID that matches any of our custom environments
  for key, env in pairs(custom_amsthm_envs) do
    local prefix = key .. "-"
    if id:sub(1, #prefix) == prefix then
      local label = ""
      local current_number = ""
      local title = ""
      local content_without_title = {}
      
      -- Handle numbering and cross-references
      if env.numbered then
        amsthm_counters[key] = amsthm_counters[key] + 1
        current_number = tostring(amsthm_counters[key])
        current_counters[key][id] = current_number
        label = "\\label{" .. id .. "}"
      end
      
      -- Extract title from first header (## Title) and prepare content
      for i, block in ipairs(div.content) do
        if i == 1 and block.t == "Header" and block.level == 2 then
          -- Extract title from the header
          title = " (" .. pandoc.utils.stringify(block.content) .. ")"
          -- Skip this header in the content
        else
          table.insert(content_without_title, block)
        end
      end
      
      -- Create LaTeX environment
      local latex_begin
      if title ~= "" then
        latex_begin = "\\begin{" .. env.latex_name .. "}[" .. title:gsub("^ %(", ""):gsub("%)$", "") .. "]" .. label
      else
        latex_begin = "\\begin{" .. env.latex_name .. "}" .. label
      end
      local latex_end = "\\end{" .. env.latex_name .. "}"
      
      -- For LaTeX output
      if FORMAT:match("latex") then
        local content = {}
        table.insert(content, pandoc.RawBlock("latex", latex_begin))
        for _, block in ipairs(content_without_title) do
          table.insert(content, block)
        end
        table.insert(content, pandoc.RawBlock("latex", latex_end))
        return content
      else
        -- For HTML output, create a styled div matching Quarto's built-in format
        local html_class = "theorem"
        local html_title = env.name
        if env.numbered then
          html_title = html_title .. " " .. current_number
        end
        if title ~= "" then
          html_title = html_title .. title
        end
        
        local content = {}
        
        -- Create the first paragraph with theorem title span and content
        if #content_without_title > 0 and content_without_title[1].t == "Para" then
          -- If first block is a paragraph, merge the title with it
          local first_para = content_without_title[1]
          local title_span = pandoc.Span(
            {pandoc.Strong({pandoc.Str(html_title)})},
            {class = "theorem-title"}
          )
          
          -- Create new paragraph content with title span first
          local new_content = {title_span, pandoc.Space()}
          for _, inline in ipairs(first_para.content) do
            table.insert(new_content, inline)
          end
          
          table.insert(content, pandoc.Para(new_content))
          
          -- Add remaining blocks
          for i = 2, #content_without_title do
            table.insert(content, content_without_title[i])
          end
        else
          -- If no content or first block is not paragraph, create title-only paragraph
          local title_span = pandoc.Span(
            {pandoc.Strong({pandoc.Str(html_title)})},
            {class = "theorem-title"}
          )
          table.insert(content, pandoc.Para({title_span}))
          
          -- Add all content blocks
          for _, block in ipairs(content_without_title) do
            table.insert(content, block)
          end
        end
        
        return pandoc.Div(content, {class = html_class, id = id})
      end
    end
  end
  return div
end

-- Function to handle cross-references to custom amsthm environments
function handle_amsthm_cite(cite)
  for i, citation in ipairs(cite.citations) do
    local id = citation.id
    for key, env in pairs(custom_amsthm_envs) do
      local prefix = key .. "-"
      if id:sub(1, #prefix) == prefix then
        if FORMAT:match("latex") then
          return pandoc.RawInline("latex", env.reference_prefix .. "~\\ref{" .. id .. "}")
        else
          -- For HTML, create a link matching Quarto's built-in format
          local counter_val = current_counters[key][id] or "?"
          return pandoc.Link(
            {pandoc.Str(env.reference_prefix), pandoc.Str("\u{00A0}"), pandoc.Str(counter_val)}, 
            "#" .. id, 
            "", 
            {class = "quarto-xref"}
          )
        end
      end
    end
  end
  return cite
end

-- Main filter functions
return {
  {
    Meta = function(meta)
      process_custom_amsthm(meta)
      
      -- Add LaTeX headers for custom environments
      if FORMAT:match("latex") then
        local latex_headers = generate_latex_headers()
        if latex_headers ~= "" then
          if meta["header-includes"] then
            if type(meta["header-includes"]) == "table" then
              table.insert(meta["header-includes"], pandoc.RawBlock("latex", latex_headers))
            else
              meta["header-includes"] = {meta["header-includes"], pandoc.RawBlock("latex", latex_headers)}
            end
          else
            meta["header-includes"] = pandoc.RawBlock("latex", latex_headers)
          end
        end
      end
      
      return meta
    end
  },
  {
    Div = handle_amsthm_div
  },
  {
    Cite = handle_amsthm_cite
  }
}
