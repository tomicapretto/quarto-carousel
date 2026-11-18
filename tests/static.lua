-- Checks the native PDF fallback after the carousel filter.
return {{ Pandoc = function(doc)
  if quarto.doc.is_format("html") then return doc end
  local images = {}
  local breaks = 0
  doc:walk({
    Image = function(image)
      if image.src:match("assets/") then
        assert(image.attributes.width == "85%", "Static images must use percentage widths")
        assert(image.attributes.height == nil, "Static images must not retain pixel heights")
        table.insert(images, image.src)
      end
    end,
    LineBreak = function() breaks = breaks + 1 end,
    RawBlock = function(block) assert(block.format ~= "html", "Unexpected raw HTML block") end,
    RawInline = function(inline) assert(inline.format ~= "html", "Unexpected raw HTML inline") end,
    Div = function(div) assert(not div.classes:includes("carousel"), "Carousel class survived") end,
  })
  assert(#images == 6, "Missing static images, including Markdown or figure syntax")
  for i, source in ipairs(images) do
    local name = i % 2 == 1 and "test-image.svg" or "bariloche_emilio-lujan_cropped.jpg"
    assert(source:sub(-#name) == name, "Static steps changed order")
  end
  assert(breaks == 2, "Caption <br> must become native LineBreak elements")
  return doc
end }}
