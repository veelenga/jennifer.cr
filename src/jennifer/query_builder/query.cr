require "./*"

module Jennifer
  module QueryBuilder
    abstract class IQuery
    end

    class Query(T) < IQuery
      include Enumerable(T)

      @tree : Criteria | LogicOperator | Nil
      @having : Criteria | LogicOperator | Nil
      @table = ""
      @limit : Int32?
      @offset : Int32?

      property :tree

      def initialize
        @tree = nil
        @joins = [] of Join
        @order = {} of String => String
        @relations = [] of String
        @group = {} of String => Array(String)
        @having = nil
      end

      def initialize(@table : String)
        initialize
      end

      def table
        @table.empty? ? T.table_name : @table
      end

      def empty?
        @tree.nil? && @limit.nil? && @offset.nil? && @joins.empty? && order.empty? && @relations.empty?
      end

      def to_s
        (@tree || "").to_s
      end

      def to_sql
        if @tree
          @tree.not_nil!.to_sql
        else
          ""
        end
      end

      def sql_args
        if @tree
          @tree.not_nil!.sql_args
        else
          [] of DB::Any
        end
      end

      def sql(query : String, args = [] of DB::Any)
        RawSql.new(query, args.map { |e| e.as(DB::Any) })
      end

      def c(name : String)
        Criteria.new(name, table)
      end

      def c(name : String, table_name : String)
        Criteria.new(name, table_name)
      end

      def set_tree(other : Criteria | LogicOperator | IQuery)
        other = other.tree if other.is_a? IQuery
        @tree = if !@tree.nil? && !other.nil?
                  @tree.as(Criteria | LogicOperator) & other
                else
                  other
                end
        self
      end

      def set_tree(other : Nil)
        raise ArgumentError
      end

      def where(&block)
        ac = Query(T).new(table)
        other = with ac yield
        set_tree(other)
      end

      def join(klass : Class, type = :inner)
        join(klass.table_name, type) { with self yield }
      end

      def join(_table : String, type = :inner)
        ac = Query(T).new(_table)
        other = with ac yield
        @joins << Join.new(_table, other, type)
        self
      end

      def left_join(klass : Class, &block)
        join(klass, :left) { with self yield }
      end

      def left_join(_table : String)
        join(_table, :left) { with self yield }
      end

      def right_join(klass : Class)
        join(klass, :right) { with self yield }
      end

      def with(*arr)
        @relations += arr.map(&.to_s).to_a
        self
      end

      def relation(name, type = :inner)
        name = name.to_s
        rel = T.relation(name)
        join(rel.model_class, type) { rel.condition_clause.not_nil! }
        self
      end

      def includes(*names)
        names.each do |name|
          includes(name)
        end
        self
      end

      def includes(name : String | Symbol)
        relation(name).with(name.to_s)
      end

      def having
        ac = Query(T).new(table)
        other = with ac yield
        @having = other
        self
      end

      def destroy
        delete
      end

      def delete
        body = from_clause + body_section
        ::Jennifer::Adapter.adapter.exec "DELETE #{body}", select_args
      end

      def exists?
        @limit = 1
        body = from_clause + body_section
        query = "SELECT EXISTS(SELECT 1 #{body})"
        ::Jennifer::Adapter.adapter.scalar(query, select_args) == 1
      rescue e
        puts query
        raise e
      end

      def count : Int32
        body = from_clause + body_section
        ::Jennifer::Adapter.adapter.scalar("SELECT COUNT(*) #{body}", select_args).as(Int64).to_i
      end

      def distinct(column, _table)
        query = "SELECT DISTINCT #{_table}.#{column}\n" + from_clause + body_section
        result = [] of DB::Any | Int16 | Int8
        ::Jennifer::Adapter.adapter.query(query, select_args) do |rs|
          rs.each do
            result << ::Jennifer::Adapter.adapter_class.result_to_array(rs)[0]
          end
        end
        result
      end

      def distinct(column : String)
        distinct(column, table)
      end

      def group(column : String)
        arr = _groups(table)
        arr << column
        self
      end

      def group(*columns)
        _groups(table).concat(columns.to_a)
        self
      end

      def group(**columns)
        columns.each do |t, fields|
          arr = _groups(t.to_s)
          arr += fields
        end
        self
      end

      def limit(count)
        @limit = count
        self
      end

      def offset(count)
        @offset = count
        self
      end

      def first
        @limit = 1
        to_a[0]?
      end

      def first!
        @limit = 1
        to_a[0] # TODO: change out of bound to own exception
      end

      # don't properly works if using "with"
      def pluck(*fields)
        arr = fields.map(&.to_s)
        result = [] of Hash(String, DB::Any | Int16 | Int8)
        ::Jennifer::Adapter.adapter.query(select_query, select_args) do |rs|
          rs.each do
            h = {} of String => DB::Any | Int8 | Int16
            res_hash = ::Jennifer::Adapter.adapter_class.result_to_hash(rs)
            arr.each do |k|
              h[k] = res_hash[k]
            end
            result << h
          end
        end
        result
      end

      # def pluck(**fields)
      #  hash = fields.to_h
      #  result = [] of Hash(String, DB::Any | Int16 | Int8)
      #  ::Jennifer::Adapter.adapter.query(select_query, select_args) do |rs|
      #    rs.each do
      #      h = {} of String => DB::Any | Int8 | Int16
      #      res_hash = ::Jennifer::Adapter.adapter_class.result_to_hash(rs)
      #      fields.each do |k, v|
      #        h[k.to_s] = res_hash[k.to_s]
      #      end
      #      result << h
      #    end
      #  end
      #  result
      # end

      def order(**opts)
        order(opts.to_h)
      end

      def order(opts : Hash(String | Symbol, String | Symbol))
        opts.each do |k, v|
          @order[k.to_s] = v.to_s
        end
        self
      end

      def update(options : Hash)
        str = "UPDATE #{table} SET #{options.map { |k, v| k.to_s + "= ?" }.join(", ")}\n"
        args = [] of DB::Any
        options.each do |k, v|
          args << v
        end
        str += body_section
        args += select_args
        ::Jennifer::Adapter.adapter.exec(str, args)
      end

      def update(**options)
        update(options.to_h)
      end

      def select_query
        select_clause + body_section
      end

      def group_clause
        if @group.empty?
          ""
        else
          fields = @group.map { |t, fields| fields.map { |f| "#{t}.#{f}" }.join(", ") }.join(", ") # TODO: make building better
          "GROUP BY #{fields}\n"
        end
      end

      def having_clause
        return "" unless @having
        "HAVING #{@having.not_nil!.to_sql}\n"
      end

      def select_clause
        tables = [table]
        tables += @relations.map { |r| T.relations[r].table_name } unless @relations.empty?
        "SELECT #{tables.map { |e| e + ".*" }.join(", ")}\n" + from_clause
      rescue e : KeyError
        raise "Unknown relation #{(@relations - T.relations.keys).first}"
      end

      def from_clause
        "FROM #{table}\n"
      end

      def body_section
        where_clause + join_clause + order_clause + limit_clause + group_clause + having_clause
      end

      def join_clause
        @joins.map(&.to_sql).join(' ')
      end

      def where_clause
        @tree ? "WHERE #{@tree.not_nil!.to_sql}\n" : ""
      end

      def limit_clause
        str = ""
        str += "LIMIT #{@limit}\n" if @limit
        str += "OFFSET #{@offset}\n" if @offset
        str
      end

      def order_clause
        @order.empty? ? "" : "ORDER BY #{@order.map { |k, v| "#{k} #{v.upcase}" }.join(", ")}\n"
      end

      def select_args
        args = [] of DB::Any
        args += @tree.not_nil!.sql_args if @tree
        @joins.each do |join|
          args += join.sql_args
        end
        args += @having.not_nil!.sql_args if @having
        args
      end

      def each
        to_a.each do |e|
          yield e
        end
      end

      def each_result_set
        ::Jennifer::Adapter.adapter.query(select_query, select_args) do |rs|
          rs.each do
            yield rs
          end
        end
      end

      def to_a
        return to_a_with_relations if @relations.size > 0
        result = [] of T
        ::Jennifer::Adapter.adapter.query(select_query, select_args) do |rs|
          rs.each do
            result << T.new(rs)
          end
        end
        result
      rescue e
        puts "Broken query:"
        puts select_query
        raise e
      end

      # ========= private ==============

      private def _groups(name)
        @group[name] ||= [] of String
      end

      private def to_a_with_relations
        h_result = {} of String => T
        nested_hash = @relations.map { |e| {} of String => Bool }
        ::Jennifer::Adapter.adapter.query(select_query, select_args) do |rs|
          rs.each do
            h = ::Jennifer::Adapter.adapter_class.table_row_hash(rs)
            main_field = T.primary_field_name
            next unless h[T.table_name][main_field]?

            obj = (h_result[h[T.table_name][main_field].to_s] ||= T.new(h[T.table_name], false))
            build_relations(h, nested_hash, obj)
          end
        end
        h_result.values
      end

      private def build_relations(parsed_hash, nested_hash, obj : T)
        @relations.each_with_index do |rel_name, i|
          rel = T.relations[rel_name]
          rel_class = rel.model_class
          main_field = rel_class.primary_field_name
          table_name = rel_class.table_name
          next unless parsed_hash[table_name][main_field]
          next if nested_hash[i][parsed_hash[table_name][main_field].to_s]?

          nested_hash[i][parsed_hash[table_name][main_field].to_s] = true
          obj.set_relation(rel_name, parsed_hash[table_name])
        end
      end
    end
  end
end
