function carousel_item(extra_class, duration, image, caption)
  local template = [[
  <div class="carousel-item %s" data-bs-interval="%d">
    <img src="%s" class="d-block mx-auto">
    <div class="carousel-caption d-none d-md-block">
      <p class="fw-light">%s</p>
    </div>
  </div>
  ]]
  return string.format(template, extra_class, duration, image, caption)
end


function carousel_indicator(id, index, extra_class, aria_current)
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

function carousel(id, items, duration, autoplay)
  -- Validate inputs
  if not items or #items == 0 then
    return ""
  end

  id = id or ("carousel-" .. pandoc.utils.sha1(pandoc.utils.stringify(items)))

  local data_bs_ride = autoplay
  local indicators = {}
  local slides = {}

  for i, item in ipairs(items) do
    quarto.log.output("== Handling Header ==")
    quarto.log.output(item)

    local active = (i == 1) and " active" or ""
    local aria_current = (i == 1) and ' aria-current="true"' or ""
    local caption = item.caption or ""
    -- TODO: text and image, text or image, captions, labels, etc.

    -- Indicator button
    table.insert(indicators, carousel_indicator(id, i, active, aria_current))

    -- Carousel item
    table.insert(slides, carousel_item(active, duration, item.image, caption))
  end

  -- Return empty string if no valid slides
  if #slides == 0 then
    return ""
  end


  -- carousel-dark
  return string.format(
    [[
      <div id="%s" class="carousel slide" data-bs-ride="%s">
        <div class="carousel-indicators">%s</div>
        <div class="carousel-inner">%s</div>

        <button class="carousel-control-prev" type="button" data-bs-target="#%s" data-bs-slide="prev">
          <span class="carousel-control-prev-icon" aria-hidden="true"></span>
          <span class="visually-hidden">Previous</span>
        </button>

        <button class="carousel-control-next" type="button" data-bs-target="#%s" data-bs-slide="next">
          <span class="carousel-control-next-icon" aria-hidden="true"></span>
          <span class="visually-hidden">Next</span>
        </button>
      </div>
    ]],
    id, data_bs_ride, table.concat(indicators, "\n"), table.concat(slides, "\n"), id, id
  )
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

    -- quarto.log.output(el)

    local duration = tonumber(el.attributes["duration"]) or 3000
    local id = el.identifier or "carousel"
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
        end
      elseif blk.t == "Figure" and blk.content then
        -- ![caption](path) - Figures
        local img = nil
        for _, content in ipairs(blk.content) do
          if content.t == "Image" then
            img = content
            break
          end
        end

        if img and img.src and img.src ~= "" then
          local caption = pandoc.utils.stringify(blk.caption or "")
          table.insert(items, { caption = caption, image = img.src })
        end


      elseif blk.t == "Para" and blk.content and #blk.content >= 1 then
        -- ![](path) or ![](path){caption="..."}
        for _, content in ipairs(blk.content) do
          if content.t == "Image" then
            local caption = pandoc.utils.stringify(content.caption or "") or content.attributes.caption or ""
            local src = content.src or ""
            if src ~= "" then
              table.insert(items, { caption = caption, image = src })
            end
            break
          end
        end
      end
    end
    local html = carousel(id, items, duration, autoplay)
    return pandoc.RawBlock("html", html)
  end
end