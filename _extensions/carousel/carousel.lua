
--- @file carousel.lua
--- @brief Quarto filter to create Bootstrap Carousels in HTML documents
--- @description This filter allows you to create carousels using Bootstrap in a Quarto document.
--- It supports carousels with images, text, and captions.
--- The filter allows users to customize both the carousel and the individual slides.

--- Extension name constant
--- @type string
local EXTENSION_NAME = "quarto-carousel"

--- Generate unique carousel ID
--- @type integer
local carousel_count = 0

--- Generate unique ID for carousels
---
--- @return string The ID with format `"quarto-carousel-%d"`
local function unique_carousel_id()
  carousel_count = carousel_count + 1
  return "quarto-carousel-" .. tostring(carousel_count)
end

--- Create slide for the carousel
---
--- @param is_active boolean Whether the slide is active (viewable).
--- @param duration number Time delay before cycling to the next slide (ms).
--- @param style string|nil Optional styles that are added to the div.
--- @return pandoc.Div out A div with class `"carousel-item"` and optionally `"active"`.
local function create_slide(is_active, duration, style)
  local classes = {"carousel-item"}
  local attrs = {["data-bs-interval"] = tostring(duration)}
  if is_active then
    table.insert(classes, "active")
  end

  if style and style ~= "" then
    attrs["style"] = style
  end
  local out = pandoc.Div({}, pandoc.Attr("", classes, attrs))
  return out
end

--- Create Image element from source string.
---
--- @param source string The source of the image.
--- @return pandoc.Image img The image, with classes `{"d-block", "mx-auto"}`.
local function create_image(source)
  local img = pandoc.Image({}, source, "", pandoc.Attr("", {"d-block", "mx-auto"}))
  return img
end

--- Create overlay Div
---
--- @param content table A table with arbitrary contents to put in a div.
--- @return pandoc.Div out A div with class `"overlay"`. Its contents are on top of the slide.
local function create_overlay(content)
  inner_div = pandoc.Div(content, pandoc.Attr("", {"fs-2", "fw-bold"}))
  local out = pandoc.Div(inner_div, pandoc.Attr("", {"overlay"}))
  return out
end

--- Create caption div
---
--- @param text string The text for the slide caption.
--- @return pandoc.Div out A div with classes `{"carousel-caption", "d-none", "d-md-block"}`.
local function create_caption(text)
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

  local out = pandoc.Div(
    { pandoc.Para(inlines) },
    pandoc.Attr("", {"carousel-caption", "d-none", "d-md-block"})
  )
  return out
end

--- Create navigation button
---
---@param id string The ID of the carousel associated with the navigation button.
---@param index integer The slide index.
---@param is_active boolean Whether the slide is active (viewable).
---@return pandoc.RawBlock out A block containing a button for carousel navigation
local function create_indicator(id, index, is_active)
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
  local out = pandoc.RawBlock("html", button)
  return out
end

--- Create control buttons
---
---@param id string The ID of the carousel associated with the control buttons.
---@return pandoc.RawBlock, pandoc.RawBlock ... The control buttons.
local function create_controls(id)
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
  return pandoc.RawBlock("html", prev), pandoc.RawBlock("html", next)
end

--- Process `pandoc.Div` with the carousel filter
---
---@param el pandoc.Div The div to process.
---@return pandoc.RawBlock|nil out `The raw HTML block if the filter is effectively applied, else `nil`.
local function process_div(el)
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
  local style = el.attributes["style"] or nil
  local is_framed = el.classes:includes("framed")
  local is_dark = el.classes:includes("dark")

  -- Initialize empty tables for slides and indicators. There's one indicator per slide.
  local slides = {}
  local indicators = {}
  for i, block in ipairs(el.content or {}) do
    if block.classes:includes("carousel-item") then
      local image_source = block.attributes["image"] or ""
      local caption = block.attributes["caption"] or ""
      local slide_duration = block.attributes["duration"] or duration
      local slide_style = block.attributes["style"] or nil

      local slide = create_slide(i == 1, slide_duration, slide_style)
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

  local classes = {"carousel"}
  if is_dark then
    table.insert(classes, "carousel-dark")
  end
  table.insert(classes, "slide")

  local div_carousel_attr = pandoc.Attr(id, classes, attrs)
  local div_carousel = pandoc.Div({}, div_carousel_attr)

  -- Make it framed, if necessary
  if is_framed then
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
    local control_prev, control_next = create_controls(id)
    div_carousel.content:insert(control_prev)
    div_carousel.content:insert(control_next)
  end

  local out = pandoc.RawBlock("html", pandoc.write(pandoc.Pandoc(div_carousel), "html"))
  return out
end


--- Pandoc filter configuration
return {
  { Div = process_div }
}