require 'damerau-levenshtein'
require 'time'

# Реализация BK дерева
class BKTree
  def initialize
    @root = nil
    # Расстояние Дамерау-Левенштейна для вычислений
    @distance = DamerauLevenshtein.method(:distance)
  end

  # Вставка в дерево
  def insert(word)
    if @root.nil?
      # Пустое - начинаем с корня
      @root = Node.new(word)
    else
      @root.insert(word, @distance)
    end
  end

  # Поиск слов, близких к нужному с учетом максимального расстояния
  def search(target, max_distance)
    return [] if @root.nil?

    @root.search(target, max_distance, @distance)
  end

  # Нода BK дерева
  class Node
    attr_reader :word, :children

    def initialize(word)
      @word = word
      @children = {}
    end

    # Вставка в ноду
    def insert(word, distance)
      # Вычисление расстояния до текущего слова
      dist = distance.call(@word, word)

      if @children[dist]
        # Если есть нода с таким расстоянием то рекурсивно вставляем
        @children[dist].insert(word, distance)
      else
        # Если нет, то создаем
        @children[dist] = Node.new(word)
      end
    end

    # Поиск "близких" слов
    def search(target, max_distance, distance)
      # Находим расстояние до текущей ноды
      dist_to_node = distance.call(@word, target)
      results = []

      # Если расстояние до ноды <= максимального - учитываем
      results << @word if dist_to_node <= max_distance

      # Задаем границы для поиска по расстоянию
      lower_bound = dist_to_node - max_distance
      upper_bound = dist_to_node + max_distance

      # Рекурсивный проход по детям ноды
      @children.each do |dist, child|
        if dist.between?(lower_bound, upper_bound)
          results.concat(child.search(target, max_distance, distance))
        end
      end

      results
    end
  end
end

# Основной класс
class LogMuncher
  def initialize(log_file)
    @log_file = log_file
    # Храним все голоса
    @votes = Hash.new(0)
    # Инициализация BK дерева
    @bk_tree = BKTree.new
    # Количество вхождений имен
    @name_occurrences = Hash.new(0)
  end

  # Преобразуем имя в удобную для обработки форму
  def process_name(name)
    # Удаляем ошибочно попавшие в него латинские буквы
    cleaned_name = name.gsub(/[a-zA-Z]/, '')
    # Добавляем пробелы между словами
    cleaned_name.gsub!(/([a-zа-я])([A-ZА-Я])/, '\1 \2')
    cleaned_name
  end

  # Метод для обработки логов
  def process_logs
    # Читаем файл построчно
    File.foreach(@log_file) do |line|
      if line =~ /vote => (.+)/
        # Извлекаем имя
        name = process_name($1.strip)
        # Ищем ближайшее к этому имени
        closest_name = find_closest_participant(name)

        if closest_name.nil?
          # Если не нашлось - добавляем новое в дерево
          @bk_tree.insert(name)
          @votes[name] += 1
          @name_occurrences[name] += 1
        else
          if DamerauLevenshtein.distance(name, closest_name) <= 2
            # Если найденное подходящее и более длинное имя - складываем голоса
            if name.length > closest_name.length
              @votes[name] += @votes[closest_name]
              @votes.delete(closest_name)
              @votes[name] += 1
              @name_occurrences[name] += 1
              @bk_tree.insert(name) # Обновляем дерево
            else
              # Если подходящее имя более короткое - увеличиваем счетчик
              @votes[closest_name] += 1
              @name_occurrences[closest_name] += 1
            end
          else
            # Не нашли подходящих - добавляем как новое
            @votes[name] += 1
            @name_occurrences[name] += 1
          end
        end
      end
    end
  end

  # Нахождение ближайшего участника по имени
  def find_closest_participant(name)
    # Ищем в BK дереве
    results = @bk_tree.search(name, 2)
    # Берем имя с минимальным расстоянием и наибольшей длиной
    results.min_by do |participant|
      [DamerauLevenshtein.distance(name, participant), -participant.length]
    end
  end

  # Восстановление имен
  def consolidate_names
    # Сортируем имена по частоте вхождений по убыванию
    name_frequency = @name_occurrences.sort_by { |_, count| -count }.to_h

    # Проходим по всем
    all_names = @name_occurrences.keys
    name_map = {}

    all_names.each do |name|
      next if name_map[name] # Пропускаем уже объединенные имена

      # Находим похожие на него имена
      candidates = find_similar_names(name, name_frequency, 5)
      # Выбираем правильное имя из всех возможных
      correct_name = choose_correct_name(candidates)

      # Обновляем мапу
      candidates.each { |candidate| name_map[candidate] = correct_name }
    end

    # Складываем голоса по восстановленным именам
    consolidated_votes = Hash.new(0)
    @votes.each do |name, count|
      correct_name = name_map[name] || name
      consolidated_votes[correct_name] += count
    end

    consolidated_votes
  end

  # Метод для нахождения похожих имен с учетом расстояния
  def find_similar_names(name, frequency_map, max_distance)
    # Находим имена, которые близки к текущему
    candidates = frequency_map.keys.select do |candidate|
      DamerauLevenshtein.distance(name, candidate) <= max_distance
    end
    candidates
  end

  # Метод для выбора правильного имени из возможных
  def choose_correct_name(candidates)
    # Берем с максимальной частотой и длиной
    candidates.max_by do |candidate|
      [@name_occurrences[candidate], candidate.length]
    end
  end

  # Вывод результата
  def print_results
    # Получаем объединенные результаты голосования и сортируем по убыванию
    consolidated_votes = consolidate_names
    sorted_results = consolidated_votes.sort_by { |_, votes| -votes }

    # Принтим результаты
    sorted_results.each do |name, votes|
      puts "#{name}: #{votes} голосов"
    end

    # Для дебага принтим суммарное количество голосов (должно равняться количеству строк в файле)
    total_votes = consolidated_votes.values.sum
    puts "\nОбщее количество голосов: #{total_votes}"
  end
end

start_time = Time.now


log_muncher = LogMuncher.new('.idea/log.txt')
log_muncher.process_logs
log_muncher.print_results

end_time = Time.now

execution_time = end_time - start_time
puts "\nВремя выполнения программы: #{execution_time.round(2)} секунд"