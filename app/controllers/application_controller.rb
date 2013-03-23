class ApplicationController < ActionController::Base
  protect_from_forgery
  after_filter :set_content_type

  def set_content_type
    if request.format == :html
      response.content_type = "application/xhtml+xml"
    end
  end

  def get_page_number(params)
    if params[:page]
      i = params[:page].to_i
      if i > 0
        return i
      end
    end
    return 1
  end

  def get_page_count(params)
    if params[:count]
      i = params[:count].to_i
      if i && i > 0 && i <= 100
        return i
      end
    end
    return Settings.page_per
  end
end
