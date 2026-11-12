# Keep table structure when Action Text sanitizes HTML content attachments.
Rails.application.config.after_initialize do
  helper = ActionText::ContentHelper
  defaults = helper.sanitizer.class.allowed_tags.to_a + [ ActionText::Attachment.tag_name, "figure", "figcaption" ]
  helper.allowed_tags = (helper.allowed_tags || defaults) | %w[table thead tbody tfoot tr th td]
end
