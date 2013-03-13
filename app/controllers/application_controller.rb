class ApplicationController < ActionController::Base
  protect_from_forgery
  after_filter :set_content_type

  def set_content_type
    if request.format == :html
      response.content_type = "application/xhtml+xml"
    end
  end

  def get_page_number(params)
    if params[:page] && i = params[:page].to_i
      if i > 0
        return i
      end
    end
    return 1
  end

  def get_user_cache(items)
    Hash[
      User.where(items
        .map{|m| [m.user_id, m.favorites.map{|u| u.user_id}, m.retweets.map{|u| u.user_id}]}
        .flatten
        .uniq.map{|m| "id = #{m}"}.join(" OR "))
      .map{|m| [m.id, m]}
    ]
  end
end
