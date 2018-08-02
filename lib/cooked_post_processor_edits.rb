require_dependency 'cooked_post_processor'
CookedPostProcessor.class_eval do
  def extract_post_image
    (extract_images_for_post -
    @doc.css("img.thumbnail") -
    @doc.css("img.site-icon") -
    @doc.css("img.avatar")).first
  end

  def determine_image_size(img)
    get_size_from_attributes(img) ||
    get_size_from_image_sizes(img["src"], @opts[:image_sizes]) ||
    get_size(img["src"])
  end

  def valiate_image_for_previews(img)
    w, h = determine_image_size(img)
    w >= 100 && h >= 100
  end

  def update_post_image
    extracted = extract_post_image

    img = extracted if valiate_image_for_previews(extracted)

    if @has_oneboxes
      cooked = PrettyText.cook(@post.raw)

      if img
        ## We need something more specific to identify the image with
        img_id = img
        src = img.attribute("src").to_s
        img_id = src.split('/').last.split('.').first if src
      end

      prior_oneboxes = []
      Oneboxer.each_onebox_link(cooked) do |url, element|
        if !img || (img && cooked.index(element).to_i < cooked.index(img_id).to_i)
          html = Nokogiri::HTML::fragment(Oneboxer.cached_preview(url))
          prior_oneboxes = html.css('img')
        end
      end

      if prior_oneboxes.any?
        prior_oneboxes = prior_oneboxes.reject do |html|
          class_str = html.attribute('class').to_s
          class_str.include?('site-icon') || class_str.include?('avatar')
        end

        if prior_oneboxes.any? && valiate_image_for_previews(prior_oneboxes.first)
          img = prior_oneboxes.first
        end
      end
    end

    if img.blank?
      @post.update_column(:image_url, nil)

      if @post.is_first_post?
        @post.topic.update_column(:image_url, nil)
        ListHelper.remove_topic_thumbnails(@post.topic)
      end
    elsif img["src"].present?
      url = img["src"][0...255]
      @post.update_column(:image_url, url) # post

      if @post.is_first_post?
        @post.topic.update_column(:image_url, url) # topic
        return if SiteSetting.topic_list_hotlink_thumbnails ||
                  !SiteSetting.topic_list_previews_enabled

        ListHelper.create_topic_thumbnails(@post, url)
      end
    end
  end
end
