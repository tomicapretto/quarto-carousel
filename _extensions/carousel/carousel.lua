
--- @file carousel.lua
--- @brief Interactive HTML carousels and native static steps for other formats
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

--- Create overlay Div
---
--- @param content table A table with arbitrary contents to put in a div.
--- @return pandoc.Div out A div with class `"overlay"`. Its contents are on top of the slide.
local function create_overlay(content)
  local inner_div = pandoc.Div(content, pandoc.Attr("", {"fs-2", "fw-bold"}))
  local out = pandoc.Div(inner_div, pandoc.Attr("", {"overlay"}))
  return out
end

--- Extract slides once for both interactive and static output.
local function extract_items(el)
  local items = {}
  for _, block in ipairs(el.content) do
    if block.t == "Div" and
      (block.classes:includes("carousel-item") or block.classes:includes("item")) then
      local source = block.attributes["image"]
      table.insert(items, {
        image = source and source ~= "" and pandoc.Image({}, source) or nil,
        caption = pandoc.read(block.attributes["caption"] or "", "html").blocks,
        content = block.content,
        duration = block.attributes["duration"],
        style = block.attributes["style"],
      })
    elseif block.t == "Figure" or (block.t == "Div" and
      block.attributes["__quarto_custom_type"] == "FloatRefTarget") then
      -- Keep the figure node intact so Quarto can number it and resolve refs.
      table.insert(items, {
        figure = block,
        caption = pandoc.Blocks({}),
        content = pandoc.Blocks({}),
      })
    elseif block.t == "Para" or block.t == "Plain" then
      for _, inline in ipairs(block.content) do
        if inline.t == "Image" then
          table.insert(items, {
            image = inline,
            caption = #inline.caption > 0 and pandoc.Blocks({pandoc.Para(inline.caption)})
              or pandoc.Blocks({}),
            content = pandoc.Blocks({}),
          })
        end
      end
    end
  end
  return items
end

--- Use native Pandoc elements so every output writer can retain the steps.
local function static_carousel(items, id)
  local blocks = pandoc.Blocks({})
  for _, item in ipairs(items) do
    if item.figure then
      local figure = quarto._quarto.ast.walk(item.figure, {
        Image = function(image)
          image.attributes["width"] = "85%"
          image.attributes["height"] = nil
          return image
        end,
      })
      blocks:insert(figure)
    elseif item.image then
      local image = item.image:clone()
      image.caption = {pandoc.Str(pandoc.utils.stringify(item.caption))}
      image.attributes["width"] = "85%"
      image.attributes["height"] = nil
      blocks:insert(pandoc.Para({image}))
    end
    if not item.figure then
      -- Plain captions otherwise run into the following image in Typst.
      local caption = pandoc.Div(item.caption):walk({
        Plain = function(block) return pandoc.Para(block.content) end
      })
      blocks:extend(caption.content)
    end
    blocks:extend(item.content)
  end
  return pandoc.Div(blocks, pandoc.Attr(id))
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
---@return pandoc.Div|nil
local function process_div(el)
  if not el.classes:includes("carousel") then
    return nil
  end

  local items = extract_items(el)
  local id = el.identifier ~= "" and el.identifier or unique_carousel_id()
  if not quarto.doc.is_format("html") then
    return static_carousel(items, id)
  end

  if not quarto.doc.has_bootstrap() then
    return nil
  end
  quarto.doc.add_html_dependency({
    name = "carousel",
    version = "1.1.0",
    stylesheets = {"quarto-carousel.css"},
    scripts = {"quarto-carousel.js"},
  })

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
  for i, item in ipairs(items) do
    local slide = create_slide(i == 1, item.duration or duration, item.style)
    local indicator = create_indicator(id, i, i == 1)

    if item.figure then
      slide.classes:insert("carousel-item-figure")
      slide.content:insert(item.figure)
    elseif item.image then
      local image = item.image:clone()
      image.classes:insert("d-block")
      image.classes:insert("mx-auto")
      slide.content:insert(pandoc.Para({image}))
    end
    if not item.figure and #item.caption > 0 then
      slide.content:insert(pandoc.Div(item.caption,
        pandoc.Attr("", {"carousel-caption", "d-none", "d-md-block"})))
    end
    if #item.content > 0 then
      slide.content:insert(create_overlay(item.content))
    end
    if transition == "none" then
      slide.classes:insert("no-transition")
    end
    table.insert(slides, slide)
    table.insert(indicators, indicator)
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

  -- Native blocks keep figures visible to Quarto's cross-reference pipeline.
  return div_carousel
end


--- Pandoc filter configuration
return {
  { Div = process_div }
}