-- TODO: Pass styles

--- Generate unique carousel ID
local carousel_count = 0
local function unique_carousel_id()
  carousel_count = carousel_count + 1
  return "quarto-carousel-" .. tostring(carousel_count)
end


function create_slide(is_active, duration)
  classes = {"carousel-item"}
  if is_active then
    classes = {"carousel-item", "active"}
  end
  return pandoc.Div({}, pandoc.Attr("", classes, {["data-bs-interval"] = tostring(duration)}))
end


function create_image( source)
  return pandoc.Image({}, source, "", pandoc.Attr("", {"d-block", "mx-auto"}))
end


function create_overlay(content)
  inner_div = pandoc.Div(content, pandoc.Attr("", {"fs-2", "fw-bold"}))
  outer_div = pandoc.Div(
    inner_div,
    pandoc.Attr(
      "",
      {"overlay", "d-flex", "flex-column", "align-items-center", "justify-content-center", "text-center"}
    )
  )
  return outer_div
end


function create_caption(text)
  -- NOTE: How could we make captions more flexible?

  -- Replace <br> with a newline character (\n)
  -- If the user writes '\n' it does not work.
  local clean_string = text:gsub("<br>", "\n")
  local inlines = {}
  local first = true
  for line in clean_string:gmatch("[^\n]+") do
    if not first then
      table.insert(inlines, pandoc.RawInline("html", "<br>"))
    end
    table.insert(inlines, pandoc.Str(line))
    first = false
  end

  return pandoc.Div(
    { pandoc.Para(inlines) },
    pandoc.Attr("", {"carousel-caption", "d-none", "d-md-block"})
  )
end


function create_indicator(id, index, is_active)
  -- NOTE: It is not possible to create a button using Pandoc API, so we use RawBlocks
  local extra_class = ""
  local aria_current = ""

  if is_active then
    extra_class = " active"
    aria_current = ' aria-current="true"'
  end

  local template = [[
  <button
    type="button"
    data-bs-target="#%s"
    data-bs-slide-to="%d"
    class="%s"%s
    aria-label="Slide %d"></button>
  ]]
  local button = string.format(template, id, index - 1, extra_class, aria_current, index)
  return pandoc.RawBlock("html", button)
end


function create_controls(id)
  -- NOTE: It is not possible to create a button using Pandoc API, so we use RawBlocks
  local prev = string.format([[
      <button class="carousel-control-prev" type="button"
      data-bs-target="#%s" data-bs-slide="prev">
      <span class="carousel-control-prev-icon" aria-hidden="true"></span>
      <span class="visually-hidden">Previous</span>
      </button>
    ]],
    id
  )

  local next = string.format([[
      <button class="carousel-control-next" type="button"
      data-bs-target="#%s" data-bs-slide="next">
      <span class="carousel-control-next-icon" aria-hidden="true"></span>
      <span class="visually-hidden">Next</span>
      </button>
    ]],
    id
  )
  return {pandoc.RawBlock("html", prev), pandoc.RawBlock("html", next)}
end


function Div(el)
  -- Only work with HTML output formats
  if not quarto.doc.is_format("html")
    or not quarto.doc.has_bootstrap()
    or not el.classes:includes("carousel") then
    return nil
  end

  quarto.doc.add_html_dependency({
    name = "carousel",
    version = "0.1.0",
    stylesheets = {"quarto-carousel.css"},
  })

  local id = (el.identifier ~= nil and el.identifier ~= "") and el.identifier or unique_carousel_id()
  local show_indicators = (el.attributes["indicators"]) or "true"
  local show_controls = (el.attributes["controls"]) or "true"
  local duration = tonumber(el.attributes["duration"]) or 3000
  local autoplay = el.attributes["autoplay"] or "carousel"
  local transition = el.attributes["transition"] or "default"
  local framed = el.attributes["framed"] or "false"
  local style = el.attributes["style"] or nil

  -- Initialize empty tables for slides and indicators. There's one indicator per slide.
  local slides = {}
  local indicators = {}
  for i, block in ipairs(el.content or {}) do
    if block.classes:includes("carousel-item") then
      local image_source = block.attributes["image"] or ""
      local caption = block.attributes["caption"] or ""
      local slide_duration = block.attributes["duration"] or duration

      local slide = create_slide(i == 1, slide_duration)
      local indicator = create_indicator(id, i, i == 1)

      -- Add image, if available
      if image_source and image_source ~= "" then
        slide.content:insert(create_image(image_source))
      end

      -- Add caption, if available
      if caption and caption ~= "" then
        slide.content:insert(create_caption(caption))
      end

      -- Add additional content, if it exists (there's no intervention here)
      if #block.content > 0 then
        slide.content:insert(create_overlay(block.content))
      end

      -- Remove transition, if necessary
      if transition == "none" then
        slide.classes:insert("no-transition")
      end

      -- Add the created elements (slide and indicator) to their respective tables
      table.insert(slides, slide)
      table.insert(indicators, indicator)
    end
  end

  -- Create empty div for the carousel, classes and attributes set.
  local attrs = {["data-bs-ride"] = autoplay}
  if style then
    attrs["style"] = style
  end

  local div_carousel_attr = pandoc.Attr(id, {"carousel", "carousel-dark", "slide"}, attrs)

  -- if style then
  --   table.insert(div_carousel_attr.attributes, {style = style})
  -- end

  local div_carousel = pandoc.Div({}, div_carousel_attr)



  -- Make it framed, if necessary
  if framed == "true" then
    div_carousel.classes:insert("carousel-framed")
  end

  -- Add slide indicators to carousel, if required
  if show_indicators and show_indicators ~= "false" then
    div_carousel.content:insert(
      pandoc.Div(indicators, pandoc.Attr("", {"carousel-indicators"}))
    )
  end

  -- Add slides to carousel, always
  div_carousel.content:insert(pandoc.Div(slides, pandoc.Attr("", {"carousel-inner"})))

  -- Add controls to carousel, if required
  if show_controls and show_controls ~= "false" then
    local controls_elements = create_controls(id)
    div_carousel.content:insert(controls_elements[1])
    div_carousel.content:insert(controls_elements[2])
  end

  return pandoc.RawBlock("html", pandoc.write(pandoc.Pandoc(div_carousel), "html"))
end
