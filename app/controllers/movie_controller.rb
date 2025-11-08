class MovieController < ApplicationController
  def index
    @search = search_params
    date = @search[:schedule][:date]
    date = Date.today.to_s if date.blank?
    schedule_counts = Schedule
      .where(date: date)
      .group(:film_id, :cinema_id)
      .count
    
    # コントローラーで使用する値を作成
    @movies = Movie.order(:title).where(title: @search[:title]).map do |movie|
      next if movie.schedules.blank?

      schedules_hash = cinemas.to_h do |cinema_id, _|
        count = schedule_counts[[film.id, cinema_id]] || 0
        [cinema_id, count]  # { cinema_id => count }
      end
      {
        title: film.title,
        image: film.image_link,
        schedules: schedules_hash
      }
    end
  end

  def show
    @search = search_params
    target_date = @search[:schedule][:date]
    target_date = Date.today.to_s if date.blank?
    @movie = Movie.find_by(id: @search[:id])
    @cinema_schedules = Cinema.where(schedules: {date: target_date}).order(:name)
  end

  private

  def search_params
    params.require(:movie).permit(:id, :title, schedule: [:date])
  end
end
