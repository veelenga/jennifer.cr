# Jennifer

Another one ActiveRecord pattern realization for Crystal with grate query DSL and migration mechanism.

## Installation

Add this to your application's `shard.yml`:

```yaml
dependencies:
  jennifer:
    github: imdrasil/jennifer.cr
  mysql:
    github: crystal-lang/crystal-mysql
```

Also you need to choose one of existing adapters for your db. Now the only supported one is for [mysql](https://github.com/crystal-lang/crystal-mysql) (much more preferable is PostgreSQL but from historical reason mysql was chosen).

## Usage

### Configuration

Put
```crystal
require "jennifer"
```
before you load your application configurations (or at least models). For now you need to specify all configurations using dsl but in future support of yaml configuration files for different environments will be added. So this is regular configuration for playground environment:

```crystal
Jennifer::Config.configure do |conf|
  conf.host = "localhost"
  conf.user = "root"
  conf.password = ""
  conf.adapter = "mysql"
  conf.db = "crystal"
  conf.migration_files_path = "./examples/migrations"
end
```

Default values:

| attribute | value |
| --- | --- |
| `migration_files_path` | `"./db/migrations"` |
| `host`| `"localhost"` |
| `adapter` | `"mysql"` |

### Migration

For command management Jennifer now uses [Sam](https://github.com/imdrasil/sam.cr). So in your `sam.cr` just add loading migrations and Jennifer hooks.

```crystal
require "./your_configuration_folder/*"
require "./migrations/*"
load_dependencies "./", "jennifer"
# your another tasks here
Sam.help
```

#### Commands
Now you can use next commands:

- create database
```shell
$ crystal sam.cr -- db:create
```
- drop database
```shell
$ crystal sam.cr -- db:drop
```
- run all migrations (only new ones will be run)
```shell
$ crystal sam.cr -- db:migrate
```
- generate new migration file
```shell
$ crystal sam.cr -- jennifer:migration:generate your_migration_name
```

#### Migration DSL

Generator will create template file for you with next name  pattern "timestamp_your_underscored_migration_name.cr". Empty file looks like this:
```crystal
class YourCamelcasedMigrationName20170119011451314 < Jennifer::Migration::Base
  def up
  end

  def down
  end
end

```

`up` method is needed for placing your db changes there, `down` - for reverting your changes back. For now reverting is not supported (no command yet but will be added in next version).

For now only 3 types are officially supported: `String` (`varchar`), `Int`, `Text`, `Bool`.  If you prefer using different type (e.g. `char` instead of `varchar`) you can pass `:type => :char` to options. Regular example for creating table:

```crystal
  create(:addresses) do |t|
    t.reference :contact # creates field contact_id with Int type and allows null values
    t.string :street, {:size => 20, :sql_type => "char"} # creates string field with CHAR(20) db type
    t.bool :main, {:default => false} # sets false as default value
  end
```

Allowed optional options for `bool`, `string` and `integer`:

- `:type` - internal field type description

| value | SQL interpretation |
| --- | --- |
| `:int` | `int` |
| `:string` | `varchar` |
| `:bool` | `bool` |
| `:text` | `text` |


- `:sql_type` - gets exact (except size) field type;
- `:null` - represent nullable if field (by default is false for all types and field);
- `:primary` - marks field as primary key field (could be several ones but this provides some bugs with query generation for such model - for now try to avoid this).
- `:default` - default value for field
- `:auto_increment` - marks field to use auto increment (properly works only with `Int32` fields, another crystal types have cut functionality for it);


To drop table just write
```crystal
drop(:addresses) # drops if exists
```
Altering existing table via DSL for now is not supported but you still can use plain SQL:
```crystal
execute("ALTER TABLE addresses CHANGE street st VARCHAR(20)")
```
All changes are executed one by one so you also could add data changes here (in `up` method) but if execution of `up` method fails - `down` method will be called and all process will stop - be ready for such behavior.

To be sure that your db is up to date before run tests or your application, add `Jennifer::Migration::Runner.migrate`.

### Model

Several examples of models
```crystal
class Contact < Jennifer::Model::Base
  mapping(
    id: {type: Int32, primary: true},
    name: String,
    age: {type: Int32, default: 10}
  )

  has_many :addresses, Address
  has_one :passport, Passport
end

class Address < Jennifer::Model::Base
  mapping(
    id: {type: Int32, primary: true},
    main: Bool,
    street: String,
    contact_id: {type: Int32, null: true}
  )

  table_name "addresses"
  belongs_to :contact, Contact
end

class Passport < Jennifer::Model::Base
  mapping(
    enn: {type: String, primary: true},
    contact_id: {type: Int32, null: true}
  )
  belongs_to :contact, Contact
end

```

`mapping` macros stand for describing all model attributes. If field has no extra parameter, you can just specify name and type (type in case of crystal language): `field_name: :Type`. But you can use tuple and provide next parameters:

| argument | description |
| --- | --- |
| `:type` | crystal data type (don't use question mark - for now you can use only `:null` option) |
| `:primary` | mark field as primary key (default is `false`) |
| `:null` | allows field to be `nil` (default is `false` for all fields except primary key |
| `:default` | default value which be set during creating **new** object |
| `:getter` | if getter should be created (default - `true`) |
| `:setter` | if setter should be created (default - `true`) |

It defines next methods:

| method | args | description |
| --- | --- | --- |
| `#initialize` | Hash(String \| Symbol, DB::Any), NamedTuple, MySql::ResultSet | constructors |
| `::field_count`| | number of fields |
| `::field_names`| | all fields names |
| `#{{field_name}}` | | getter |
| `#{{field_name}}=`| | setter |
| `::_{{field_name}}` | | helper method for building queries |
| `#primary` | | value of primary key field |
| `::primary` | | returns criteria for primary field (query dsl) |
| `::primary_field_name` | | name of primary field |
| `::primary_field_type` | | type of primary key |
| `#new_record?` | | returns `true` if record has `nil` primary key (is not stored to db) |
| `::create` | Hash(String \| Symbol, DB::Any), NamedTuple | creates object, stores it to db and returns it |
| `#save` | | saves object to db; returns `true` if success and `false` elsewhere |
| `#to_h` | | returns hash with all attributes |
| `#attribute` | `String \| Symbol` | returns attribute value by it's name |
| `#attributes_hash` | | returns `to_h` with deleted `nil` entries |

Automatically model is associated with table with underscored class name and "s" at the end (not perfect solution - I know it). So models like `Address` or `Mouse` should specify name using `::table_name` method in own body before using any relation.

Another one restriction - even you use "id" as primary field - mark it as primary in mapping.

#### Prepared queries (scopes)

Also you can specify prepared query statement. This feature is not tested and for now is not so flexible (far far from normal realization). You can do something like next:
```crystal
scope :query_name, { c("some_field") > 10 }
scope :query_with_arguments, [a, b], { (c("f1") == a) && (c("f2").in(b) }
```

As you can see arguments are next:

- scope (query) name
- array with scope arguments (optional - can be avoided)
- body (for where clause - you couldn't specify any `join` or any other stuff - given block will be used for `#where`)

Another one limit is that scope call can be only as root method in chain and can be only one - for now chaining scope is also impossible. So you could do only:

```crystal
ModelName.query_with_arguments("done", [1,2]).order(f1: :asc)
```

#### Relations

Relations is more ready for usage rather than scopes (I hope). There are three types of them: has_many, belongs_to and has_one. All of them have same semantic but generate slightly different methods.

They takes next arguments:

- relation name
- target class
- additional request (will be used inside of where clause) - optional
- name of foreign key - optional; by default takes table name without last symbol (it is dummy idea I know - there are a lot of bad things) + "_id", so for "addresses" table by default you will get "addresse_id" - you've got an idea I think.
- primary field name - optional;  by default it uses default primary field of class.

All relation macroses provide next methods:

- `#relation_name` - cache relation object (or array of them) and returns it;
- `#relation_name_reload` - reload relation and returns it;
- `#relation_name_query` - returns query which is used to get objects of this object relation entities form db.

Also `belongs_to` and `has_one` add extra method `#relation_name!` which also adds assertion for `nil`.

#### Destroy object

To destroy object use `#delete` or `#destroy` it behaves same way as for queries (will be described in next section). To destroy several objects by their ids use class method:

```crystal
ids = [1, 20, 18]
Contact.destroy(*ids)
Address.delete(1)
```
Also there is `::destroy_all` and `::delete_all` shortcut. They is useful when cleaning up db between test cases.

### Query DSL

My favorite part. Jennifer allows you to build lazy evaluated queries with chaining syntax. But some of them could be only at the and of a chain or it's beginning. Here is a list of all dsl methods:

#### Where

`all` retrieves everything (only at the beginning; creates empty request)
```crystal
Contact.all
```

Specifying where clause is really flexible. Except several things: nested queries and several operators (honestly - a lot but them are less popular then added ones).

Method accepts block which represents where clause of request (or it's part - you can chain several `where` and they will be concatenated using `AND`).

To specify field use `c` method which accepts string as field name. Also as I've mentioned after declaring model attributes you can use there names inside of block: `field_name` if it is for current table and `ModelName._field_name` if for another model. Several examples:
```crystal
Contact.where { c("id") == 1 }
Contact.where { id == 1 }
Contact.all.join(Address) { id == Address._contact_id }.where { Address._street.like("%Saint%") }
```

Also you can use `primary` to mention primary field:

```crystal
Passport.where { primary.like("%123%") }
```

Supported operators:

| Operator | SQL variant |
| --- | --- |
| `==` | `=` |
| `!=` |`!=` |
| `<` |`<` |
| `<=` |`<=` |
| `>` |`>` |
| `>=` |`>=` |
| `<=>` |`<=>` |
| `=~` | `REGEXP` |
| `&` | `AND` |
| `\|` | `OR` |

And operator-like methods:

| Method | SQL variant |
| --- | --- |
| `regexp` | `REGEXP` (accepts `String`) |
| `rlike` | `REGEXP` |
| `not_rlike` | `NOT REGEXP` |
| `not_regexp` |`NOT REGEXP` |
| `like` | `LIKE` |
| `not_like` | `NOT LIKE` |
| `is` | `IS` and provided value |
| `not` | `NOT` and provided value (or as unary operator if no one is given) |
| `in` | `IN` |

To specify exact sql query use `#sql` method:
```crystal
Contact.all.where { sql("age > ?",  [15]) & (name == "Stephan") } # it behaves like regular criteria
```

Query will be inserted "as is".

**Tips**

- all regexp methods accepts string representation of regexp
- use parenthesis for binary operators (`&` and `|`)
- `nil` given to `!=` and `==` will be transformed to `IS NOT NULL` and `IS NULL`
- `is` and `not` operator accepts next values: `:nil`, `nil`, `:unknown`, `true`, `false`
- as was said previously - no nested queries

At the end - several examples:

```crystal
Contact.where { (id > 40) & name.regexp("^[a-d]") }

Address.where { contact_id.is(nil) }
```

#### Delete and Destroy

For now they both are the same - creates delete query with given conditions. After adding callbacks `destroy` will firstly loads objects and run callbacks.

It can be only at the end of chain.

```crystal
Address.where { main.not }.delete
```

#### Joins

To join another table you can use `join` method passing model class or table name (`String`) and join type (default is `:inner`).
```crystal
field = "contact_id"
table = "passports"
Contact.all.join(Address) { id == Address._contact_id }.join(table) { id == c(field, table) }
```

Query built in block will passed to `ON` section of `JOIN`.

Also there is two shortcuts for left and right joins:

```crystal
Contact.all.left_join(Address) { id == Address._contact_id }
Contact.all.right_join("addresses") { id == Address.c("contact_id") }
```

#### Relation

To join model relation (has_many, belongs_to and has_one) pass it's name and join type:

```crystal
Contact.all.relation("addresses").relation(:passport, :left)
```

#### Includes

To preload some relation use `includes` and pass relation name:

```crystal
Contact.all.includes("addresses")
```

It is just alias for `relation(name).with(name)` methods call chain.

#### Group

```crystal
Contact.all.group("name", "id")
```

`#group` allows to add columns for `GROUP BY` section. If passing arguments are tuple of strings or just one string - all columns will be parsed as current table columns. If there is a need to group on joined table or using fields from several tables use next:

 ```crystal
 Contact.all.relation("addresses").group(addresses: ["street"], contacts: ["name"])
 ```

 Here keys should be *table names*.

#### Having

```crystal
Contact.all.group("name").having { age > 15 }
```

`#having` allows to add `HAVING` part of query. It accepts block same way as `#where` does.

#### Exists

```crystal
Contact.where { age > 42 }.exists? # returns true or false
```

`#exists?` check is there is any record with provided conditions. Can be only at the end of query chain - it hit the db.

#### Distinct

```crystal
Contant.all.distinct("age") # returns array of ages (Array(DB::Any | Int16 | Int8))
```

`#distinct` retrieves from db column values without repeats. Can accept column name and as optional second parameter - table name. Can be only as at he end of call chain - hit the db.

#### Count

```crystal
Contact.all.count
```

#### Pagination

For now you can only specify `limit` and `offset`:

```crystal
Contact.all.limit(10).offset(10)
```

#### Order

You can specifies orders to sort:
```crystal
Contact.all.order(name: :asc, id: "desc")
```

It accepts hash as well.

#### Update

You can provide hash or named tuple with new field values:
```crystal
Contact.all.update(age: 1, name: "Wonder")
```

#### Eager load

As was said Jennifer provide lazy query evaluation  so it will be performed only after trying to access to element from collection (any array method - it realize Enumerable). Also you can extract first entity via `first`. If you are sure that at least one entity in db satisfies you query you can call `#first!`.

To extract only some fields rather then entire objects use `pluck`:

```crystal
Contact.all.pluck(:id, "name")
```

It returns array of hashes with provided fields as keys ( `String => DB::Any | Int8 | Int16`)

To load relations using same query joins needed tables (yep you should specify join on condition by yourself again) and specifies all needed relations in `with` (relation name not table).

```crystal
Contact.all.left_join(Address) { id == Address._contact_id }.with(:addresses)
```

#### Transaction

Transaction mechanism provides block-like syntax:

```crystal
Jennifer::Adapter.adapter.transaction do |tx|
  Contact.create({:name => "Chose", :age => 20})
end
```

Very important this is return value of block - transaction will be committed when it returns truethy and rollback elsewhere. Also if any error was raised in block transaction will be rollbacked as well.

#### Truncation

To truncate entire table use:
```crystal
Jennifer::Adapter.adapter.truncate("contacts")
# or
Jennifer::Adapter.adapter.truncate(Contact)
```

This functionality could be useful to clear db between test cases but for now `::delete_all` works faster.

#### Important restrictions

For now you can't alias table or even field so that's why you can't join same table (this relates to relation as well).

## Development

There are still a lot of work to do. Some parts (especially sql string generation) are in wrong places. Tasks for next versions:

- [ ] move query string generation to adapter
- [ ] make access to adapter method more clear
- [ ] add PostgreSQL support
- [ ] increase test coverage to acceptable level
- [ ] add more field type:
  - [ ] Time
  - [ ] Float
  - [ ] Text
  - [ ] Json
- [ ] add internal error classes to support all exception cases
- [ ] add more operators
- [ ] add callbacks
- [ ] add validation
- [x] extend join functionality
- [ ] lazy attributes update during object saving
- [ ] make scopes more flexible
- [ ] add logger
- [ ] adds possibility for `#group` accept any sql string
- [ ] add STI
- [ ] add polymorphic associations
- [ ] add through relations
- [ ] add many-to-many relation
- [ ] add table aliasing
- [ ] add more thinks below...

## Contributing

1. [Fork it]( https://github.com/imdrasil/jennifer.cr/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request

Please ask me before start to work on some feature.

Also if you want to use it in your application (for now shard is not ready for use in production) - ping me please, my email you can find in my profile.

To run test use regular `crystal spec`. All migrations is under `./examples/migrations` directory. They all runs automatically.

## Contributors

- [imdrasil](https://github.com/[your-github-name]) Roman Kalnytskyi - creator, maintainer
