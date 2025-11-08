module MoviesHelper
  def dates_list
    Schedule.group_by(:date).pluck(:date)
  end
end
