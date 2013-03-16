class UsersController < ApplicationController
  def best
    page = get_page_number(params)
    screen_name = params[:screen_name]
    user = User.find_by(:screen_name => screen_name)
    if user
      @items = user.tweets
        .where("favorites_count > 0 or retweets_count > 0")
        .order("COALESCE(favorites_count, 0) + COALESCE(retweets_count, 0) DESC")
        .page(page)
        .per(Settings.page_per)
    else
      @items = []
    end
    @title = "@#{screen_name}'s Best Tweets"
    prepare_cache
  end

   def recent
    page = get_page_number(params)
    screen_name = params[:screen_name]
    user = User.find_by(:screen_name => screen_name)
    if user
      @items = user.tweets
        .where("favorites_count > 0 or retweets_count > 0")
        .order("id DESC")
        .page(page)
        .per(Settings.page_per)
    else
      @items = []
    end
    @title = "@#{screen_name}'s Newest Tweets"
    prepare_cache
  end

  def timeline
    page = get_page_number(params)
    screen_name = params[:screen_name]
    user = User.find_by(:screen_name => screen_name)
    if user
      @items = user.tweets
        .order("id DESC")
        .page(page)
        .per(Settings.page_per)
    else
      @items = []
    end
    @title = "@#{screen_name}'s Newest Tweets"
    prepare_cache
  end

  def my
    page = get_page_number(params)
    screen_name = params[:screen_name]
    user = User.find_by(:screen_name => screen_name)
    if user
      @items = Tweet
        .where("id IN (SELECT tweet_id FROM (" +
          "SELECT tweet_id FROM favorites WHERE user_id = #{user.id} " +
          "UNION " +
          "SELECT tweet_id FROM retweets WHERE user_id = #{user.id}" +
          ") AS rf)")
        .order("id DESC")
        .page(page)
        .per(Settings.page_per)

    else
      @items = []
    end
    @title = "@#{screen_name}'s Recent Discoveries"
    prepare_cache
  end

  def info
    screen_name = params[:screen_name]
    user = User.find_by(:screen_name => screen_name)
    if user && account = Account.find_by(:id => user.id)
      @info = get_user_info
    else
      @info = nil
    end
  end
end
