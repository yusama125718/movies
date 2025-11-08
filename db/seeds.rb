# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

Cinema.create(name: "T・ジョイ出雲", corp: "tjoy", base_url: "https://tjoy.jp/t-joy_izumo")
Cinema.create(name: "MOVIX日吉津", corp: "movix", base_url: "https://www.smt-cinema.com/site/hiezu/")
Cinema.create(name: "イオンシネマ松江", corp: "aeon_cinema", base_url: "https://theater.aeoncinema.com/schedule/v2/data/matsue/")