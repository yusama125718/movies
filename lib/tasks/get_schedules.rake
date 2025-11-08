namespace :get_schedules do
  task :execute => :environment do
    require "selenium-webdriver"

    Rails.logger.info "上映スケジュールの取得を開始します"
    puts "[INFO] 上映スケジュールの取得を開始します"
    cinemas = Cinema.all
    
    cinemas.each do |cinema|
      Movie.where(cinema: cinema).destroy_all
      Rails.logger.info "#{cinema.name}のデータを削除しました。"
      puts "[INFO] #{cinema.name}のデータを削除しました。"

      case cinema.corp
      when 'aeon_cinema'
        get_aeon_schedule(cinema)
      when 'tjoy'
        get_tjoy_schedule(cinema)
      when 'movix'
        get_movix_schedule(cinema)
      end
    end
  end

  def get_movix_schedule(cinema)
    Selenium::WebDriver.logger.output = File.join("./", "selenium.log")
    Selenium::WebDriver.logger.level = :warn

    options = Selenium::WebDriver::Chrome::Options.new
    options.add_argument('--headless')
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')
    options.add_argument('--window-size=1280x800')
    ua = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/108.0.0.0 Safari/537.36'
    options.add_argument("--user-agent=#{ua}")

    driver = Selenium::WebDriver.for(:chrome, options: options)

    driver.manage.timeouts.implicit_wait = 30 
    Selenium::WebDriver::Wait.new(timeout: 10)

    driver.get(cinema.base_url)
    Rails.logger.info "#{cinema.name}のサイトを取得しました。解析を開始します。"
    puts "[INFO] #{cinema.name}のサイトを取得しました。解析を開始します。"
    
    while(true)
      page = driver.find_element(:id, "schedule")

      # 日付を取得
      date_txt = page.find_element(:css ,".slick-track .active p").text
      target_date = Date.parse(date_txt)
      next_day_txt = (target_date + 1).strftime("%Y%m%d")
      Rails.logger.info "#{date_txt}分の解析を始めます"
      puts "[INFO] #{date_txt}分の解析を始めます"

      target = page.find_element(:class_name, "daily")

      wait = Selenium::WebDriver::Wait.new(timeout: 20)

      # セクションが出るまで待機（target配下のsection数を確認）
      wait.until do
        driver.execute_script(<<~JS, target)
          const root = arguments[0] || document;
          return root.querySelectorAll('section').length;
        JS
      end

      # === ここが重要：一度の JS 実行で「必要な値」だけを配列にして返す ===
      sections_data = driver.execute_script(<<~JS, target)
        const root = arguments[0] || document;
        const sections = root.querySelectorAll('section');
        return Array.from(sections).map(sec => {
          const h2 = sec.querySelector('.movieTitle h2');
          let title = '';

          if (h2) {
            // Node.TEXT_NODE === 3
            const textNode = Array.from(h2.childNodes)
              .find(node => node.nodeType === Node.TEXT_NODE);
            // 「（本編：124分）」のような全角カッコ内を削除
            title = textNode.textContent.trim().replace(/（本編：.+分）/, '').trim();
          }
          const image = sec.querySelector('.image img')?.src || '';
          const schedules = Array.from(sec.querySelectorAll('.select > div')).map(li => {
            const screen = li.querySelector('.block a')?.textContent.trim() || '';
            const t = li.querySelector('.time')?.textContent || '';
            const [start, end] = t.replace(/\\s+/g, '').split('～');
            return { screen, start, end };
          });
          return { title, image, schedules };
        });
      JS

      # 以降は「値」だけを使うので stale とは無縁
      sections_data.each do |sec|
        next if sec['title'].blank?
        movie = Movie.find_by(title: sec['title'], cinema: cinema)
        # 同一タイトルの映画がない場合は新規作成
        movie = Movie.create!(
          cinema:     cinema,
          title:      sec['title'],
          image_link: sec['image']
        ) if movie.nil?

        sec['schedules'].each do |sch|
          next if sch['start'].to_s.empty? || sch['end'].to_s.empty?

          Schedule.create!(
            movie:       movie,
            date:        target_date,
            screen:      sch['screen'],
            start_time:  combine_date_and_time(target_date, sch['start']),
            end_time:    combine_date_and_time(target_date, sch['end'])
          )
        end
      end

      # 次の日付ボタンを探す
      btns = driver.find_elements(:css, ".slick-track [class*='#{next_day_txt}']")

      # 見つからなければ終了（ログを出して break）
      if btns.empty?
        Rails.logger.info "'#{next_day_txt}' のボタンが存在しないため、取得を終了します。"
        puts "[INFO] '#{next_day_txt}' のボタンが存在しないため、取得を終了します。"
        break
      end

      # クリック対象
      btn = btns.first

      # クリック前に "今" のコンテンツのマーカーを掴んでおく（破棄検知用）
      old_marker = driver.find_element(:css, "section") rescue nil

      # クリック（スクロールして確実に）
      driver.execute_script("arguments[0].scrollIntoView({block: 'center'}); arguments[0].click();", btn)

      wait = Selenium::WebDriver::Wait.new(timeout: 20) # 余裕を持って20秒

      # 1) まずは「古いマーカーが破棄された（staleになった）」のを待つ
      stale_ok = false
      if old_marker
        begin
          wait.until do
            begin
              old_marker.displayed? # 何か呼ぶ→staleなら例外になる
              false
            rescue Selenium::WebDriver::Error::StaleElementReferenceError
              true
            end
          end
          stale_ok = true
        rescue Selenium::WebDriver::Error::TimeoutError
          # stale が検知できなかった場合は下の条件で続行
        end
      end

      # 2) フォールバック：次の日付が“選択状態”で、かつ section が再出現するまで待つ
      wait.until do
        active = driver.find_elements(:css, ".slick-track .active[class*='#{next_day_txt}']").any?

        has_sections = driver.execute_script("return document.querySelectorAll('section').length > 0;")
        active && has_sections
      end
    end
  end

  def get_aeon_schedule(cinema)
    # JSONを取得
    url = cinema.base_url + "schedule.json?v=" + Time.zone.now.strftime("%Y%m%d%H%M")
    json_data = URI.open(url).read
    result = JSON.parse(json_data)
    result.each do |daily_schedule|
      # 日付を取得
      date_str = daily_schedule[0]
      target_date = Date.parse(date_str)

      daily_schedule[1].each do |schedules|
        # 映画の基本情報を取得
        title = schedules[1][0]["name"]["ja"]
        # 画像リンクを取得するためにidを取得
        movie_id = schedules[1][0]["additionalProperty"].each do |values|
          if values["name"].eql?("MovieID") 
            values["value"]
            break
          end
        end
        image_link = movie_id.present? ? "https://www.aeoncinema.com/movie_images/#{movie_id}/poster400x560.jpg" : ""

        movie = Movie.find_by(title: title, cinema: cinema)
        # 同一タイトルの映画がない場合は新規作成
        movie = Movie.create!(
          cinema:     cinema,
          title:      title,
          image_link: image_link
        ) if movie.nil?

        # スケジュールを取得
        schedules[1].each do |schedule|
          start_time_str = schedule["startDate"]
          end_time_str = schedule["endDate"]
          start_time = DateTime.parse(start_time_str).new_offset(Rational(9, 24))
          end_time = DateTime.parse(end_time_str).new_offset(Rational(9, 24))
          screen = schedule["location"]["name"]["ja"]

          Schedule.create!(
            movie:       movie,
            date:        target_date,
            screen:      screen,
            start_time:  start_time.to_time,
            end_time:    end_time.to_time
          )
        end
      end
    end
    Rails.logger.info "#{cinema.name}の取得を終了します。"
    puts "[INFO] #{cinema.name}の取得を終了します。"
  end

  def get_tjoy_schedule(cinema)
    Selenium::WebDriver.logger.output = File.join("./", "selenium.log")
    Selenium::WebDriver.logger.level = :warn

    options = Selenium::WebDriver::Chrome::Options.new
    options.add_argument('--headless')
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')
    options.add_argument('--window-size=1280x800')
    ua = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/108.0.0.0 Safari/537.36'
    options.add_argument("--user-agent=#{ua}")

    driver = Selenium::WebDriver.for(:chrome, options: options)

    driver.manage.timeouts.implicit_wait = 30 
    Selenium::WebDriver::Wait.new(timeout: 10)

    driver.get(cinema.base_url)
    Rails.logger.info "#{cinema.name}のサイトを取得しました。解析を開始します。"
    puts "[INFO] #{cinema.name}のサイトを取得しました。解析を開始します。"
    
    while(true)
      page = driver.find_element(:id, "film")

      # 日付を取得
      date_txt = page.find_element(:class_name ,"calendar-active").attribute('data-date')
      target_date = Date.parse(date_txt)
      next_day_txt = (target_date + 1).strftime("%Y-%m-%d")
      Rails.logger.info "#{date_txt}分の解析を始めます"
      puts "[INFO] #{date_txt}分の解析を始めます"

      target = page.find_element(:class_name, "box-film-wapper")

      wait = Selenium::WebDriver::Wait.new(timeout: 10)

      # セクションが出るまで待機（target配下のsection数を確認）
      wait.until do
        driver.execute_script(<<~JS, target)
          const root = arguments[0] || document;
          return root.querySelectorAll('section').length;
        JS
      end

      # === ここが重要：一度の JS 実行で「必要な値」だけを配列にして返す ===
      sections_data = driver.execute_script(<<~JS, target)
        const root = arguments[0] || document;
        const sections = root.querySelectorAll('section');
        return Array.from(sections).map(sec => {
          const title = sec.querySelector('.js-title-film')?.textContent.trim() || '';
          const image = sec.querySelector('.film-img img')?.src || '';
          const schedules = Array.from(sec.querySelectorAll('li')).map(li => {
            const screen = li.querySelector('.theater-name a')?.textContent.trim() || '';
            const t = li.querySelector('.box-time p')?.textContent || '';
            const [start, end] = t.replace(/\\s+/g, '').split('～');
            return { screen, start, end };
          });
          return { title, image, schedules };
        });
      JS

      # 以降は「値」だけを使うので stale とは無縁
      sections_data.each do |sec|
        movie = Movie.find_by(title: sec['title'], cinema: cinema)
        # 同一タイトルの映画がない場合は新規作成
        movie = Movie.create!(
          cinema:     cinema,
          title:      sec['title'],
          image_link: sec['image']
        ) if movie.nil?

        sec['schedules'].each do |sch|
          next if sch['start'].to_s.empty? || sch['end'].to_s.empty?

          Schedule.create!(
            movie:       movie,
            date:        target_date,
            screen:      sch['screen'],
            start_time:  combine_date_and_time(target_date, sch['start']),
            end_time:    combine_date_and_time(target_date, sch['end'])
          )
        end
      end

      # 次の日付ボタンを探す
      btns = driver.find_elements(:css, ".calendar-slider li a[data-date='#{next_day_txt}']")

      # 見つからなければ終了（ログを出して break）
      if btns.empty?
        Rails.logger.info "data-date='#{next_day_txt}' のボタンが存在しないため、取得を終了します。"
        puts "[INFO] data-date='#{next_day_txt}' のボタンが存在しないため、取得を終了します。"
        break
      end

      # クリック対象
      btn = driver.find_element(:css, ".calendar-slider li a[data-date='#{next_day_txt}']")

      # クリック前に "今" のコンテンツのマーカーを掴んでおく（破棄検知用）
      old_marker = driver.find_element(:css, "section") rescue nil

      # クリック（スクロールして確実に）
      driver.execute_script("arguments[0].scrollIntoView({block: 'center'}); arguments[0].click();", btn)

      wait = Selenium::WebDriver::Wait.new(timeout: 20) # 余裕を持って20秒

      # 1) まずは「古いマーカーが破棄された（staleになった）」のを待つ
      stale_ok = false
      if old_marker
        begin
          wait.until do
            begin
              old_marker.displayed? # 何か呼ぶ→staleなら例外になる
              false
            rescue Selenium::WebDriver::Error::StaleElementReferenceError
              true
            end
          end
          stale_ok = true
        rescue Selenium::WebDriver::Error::TimeoutError
          # stale が検知できなかった場合は下の条件で続行
        end
      end

      # 2) フォールバック：次の日付が“選択状態”で、かつ section が再出現するまで待つ
      #    active クラス名の揺れに備えて複数候補を許容
      wait.until do
        active = driver.find_elements(
          :css,
          ".calendar-slider li a.calendar-active[data-date='#{next_day_txt}']"
        ).any?

        has_sections = driver.execute_script("return document.querySelectorAll('section').length > 0;")
        active && has_sections
      end
    end
  end

  def combine_date_and_time(date, time_str)
    hour, min = time_str.split(":").map(&:to_i)
    if hour >= 24
      date += 1
      hour -= 24
    end
    Time.zone.local(date.year, date.month, date.day, hour, min)
  end
end