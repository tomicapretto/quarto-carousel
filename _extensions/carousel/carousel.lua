function create_item(extra_class, duration, image, caption, text)
  -- Template for the image
  local image_item_template = [[
  <div class="carousel-item %s" data-bs-interval="%d">
    <img src="%s" class="d-block w-100">
    %s
  </div>
  ]]

  -- Template for the text item
  -- TODO: Check fs-3 class for text and centering classes
  -- TODO: Add no-transition class
  -- TODO: Add contained class
  local text_item_template = [[
  <div class="carousel-item %s" data-bs-interval="%d">
    <div class="d-flex align-items-center justify-content-center" style="height: 400px;">
      <div class="text-center">
        <p class="fs-3 fw-bold">
          %s
        </p>
        %s
      </div>
    </div>
  </div>
  ]]

  -- Template for the caption
  local caption_template = [[
  <div class="carousel-caption d-none d-md-block">
    <p>%s</p>
  </div>
  ]]

  local caption_el = ""
  if caption and caption ~= "" then
    caption_el = string.format(caption_template, caption)
  end

  -- If image is provided, use image template; otherwise use text template
  if image then
    local output = string.format(image_item_template, extra_class, duration, image, caption_el)
    return output
  elseif text then
    local output = string.format(text_item_template, extra_class, duration, text, caption_el)
    return output
  else
    return ""
  end
end


function create_indicator(id, index, extra_class, aria_current)
  local template = [[
  <button
    type="button"
    data-bs-target="#%s"
    data-bs-slide-to="%d"
    class="%s"%s
    aria-label="Slide %d"></button>
  ]]
  return string.format(template, id, index - 1, extra_class, aria_current, index)
end


function create_controls(id)
  local template = [[
  <button class="carousel-control-prev" type="button" data-bs-target="#%s" data-bs-slide="prev">
    <span class="carousel-control-prev-icon" aria-hidden="true"></span>
    <span class="visually-hidden">Previous</span>
  </button>
  <button class="carousel-control-next" type="button" data-bs-target="#%s" data-bs-slide="next">
    <span class="carousel-control-next-icon" aria-hidden="true"></span>
    <span class="visually-hidden">Next</span>
  </button>
  ]]
  return string.format(template, id, id)
end


function carousel(id, items, duration, autoplay)
  -- Validate inputs
  if not items or #items == 0 then
    return ""
  end

  local data_bs_ride = autoplay
  local indicators = {}
  local slides = {}

  for i, item in ipairs(items) do
    local active = (i == 1) and "active" or ""
    local aria_current = (i == 1) and ' aria-current="true"' or ""
    local caption = item.caption or ""

    -- Indicator button
    table.insert(indicators, create_indicator(id, i, active, aria_current))

    -- Carousel item - use text or image
    if item.image then
      table.insert(slides, create_item(active, duration, item.image, caption, nil))
    else
      table.insert(slides, create_item(active, duration, nil, item.caption, item.text))
    end
  end

  -- Return empty string if no valid slides
  if #slides == 0 then
    return ""
  end

  local carousel_indicators = string.format(
    "<div class='carousel-indicators'>%s</div>", table.concat(indicators, "\n")
  )
  local carousel_items = string.format(
    "<div class='carousel-inner'>%s</div>", table.concat(slides, "\n")
  )
  local carousel_controls = create_controls(id)

  local carousel_template = [[
  <div id="%s" class="carousel carousel-dark slide" data-bs-ride="%s">
    %s
    %s
    %s
  </div>
  ]]

  -- carousel-dark
  local output = string.format(
    carousel_template,
    id, data_bs_ride, carousel_indicators, carousel_items, carousel_controls
  )
  return output
end

function Div(el)
  -- Only work with HTML output formats
  if not quarto.doc.is_format("html") or not quarto.doc.has_bootstrap() then
    return nil
  end

  if el.classes:includes("carousel") then
    quarto.doc.add_html_dependency({
      name = "carousel",
      version = "0.0.1",
      stylesheets = {"quarto-carousel.css"},
    })

    local id = el.identifier or ("carousel-" .. pandoc.utils.sha1(pandoc.utils.stringify(items)))
    local duration = tonumber(el.attributes["duration"]) or 3000
    local autoplay = el.attributes["autoplay"] or "carousel"

    local items = {}
    for _, blk in ipairs(el.content or {}) do
      if blk.t == "Div" and blk.classes:includes("item") then
        -- Explicit .item div
        if blk.attributes.image and blk.attributes.image ~= "" then
          table.insert(items, {
            caption = pandoc.utils.stringify(blk.attributes.caption or ""),
            image   = blk.attributes.image,
          })
        elseif blk.attributes.text and blk.attributes.text ~= "" then
          -- Text-only item
          table.insert(items, {
            caption = pandoc.utils.stringify(blk.attributes.caption or ""),
            text    = pandoc.utils.stringify(blk.attributes.text),
          })
        end
      elseif blk.t == "Figure" and blk.content then
        -- ![caption](path) - Figures
        local img = nil
        for _, content in ipairs(blk.content) do
          -- Image can be inside a Plain or Para block
          if content.t == "Plain" or content.t == "Para" then
            for _, inner_content in ipairs(content.content) do
              if inner_content.t == "Image" then
                img = inner_content
                break
              end
            end
          -- Image is directly an Image
          elseif content.t == "Image" then
            img = content
            break
          end
          -- If an image is found, stop iterating
          if img then break end
        end

        -- If found an image, add it
        if img and img.src and img.src ~= "" then
          table.insert(items, {
            caption = pandoc.utils.stringify(blk.caption or ""),
            image = img.src
          })
        end

      elseif blk.t == "Para" and blk.content and #blk.content >= 1 then
        -- Check for image first: ![](path) or ![](path){caption="..."}
        local found_image = false
        for _, content in ipairs(blk.content) do
          if content.t == "Image" then
            local src = content.src or ""
            if src ~= "" then
              table.insert(items, {
                caption = pandoc.utils.stringify(content.caption or "") or content.attributes.caption or "",
                image = src
              })
            end
            found_image = true
            break
          end
        end

        -- If no image found, treat as text content
        if not found_image then
          local text = pandoc.utils.stringify(blk)
          if text and text ~= "" then
            table.insert(items, { text = text })
          end
        end
      end
    end

    local html = carousel(id, items, duration, autoplay)
    return pandoc.RawBlock("html", html)
  end
end