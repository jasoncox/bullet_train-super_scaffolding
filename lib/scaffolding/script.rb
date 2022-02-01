require "active_support/inflector"
require "fileutils"
require "pry"
require "colorize"
require "scaffolding"
require "#{APP_ROOT}/config/initializers/inflections"

# TODO This is a hack to allow Super Scaffolding modules to register their path. We'll do this differently once we've
# properly migrated all the code into the Rails engine structure and Rails is being initialized as part of
# `bin/super-scaffold`.
$super_scaffolding_template_paths ||= []

# TODO these methods were removed from the global scope in super scaffolding and moved to `Scaffolding::Transformer`,
# but oauth provider scaffolding hasn't been updated yet.

def legacy_replace_in_file(file, before, after)
  puts "Replacing in '#{file}'."
  target_file_content = File.read(file)
  target_file_content.gsub!(before, after)
  File.write(file, target_file_content)
end

def legacy_add_line_to_file(file, content, hook, child, parent, options = {})
  increase_indent = options[:increase_indent]
  add_before = options[:add_before]
  add_after = options[:add_after]

  transformed_file_name = file
  transformed_content = content
  transform_hook = hook

  target_file_content = File.read(transformed_file_name)

  if target_file_content.include?(transformed_content)
    puts "No need to update '#{transformed_file_name}'. It already has '#{transformed_content}'."
  else
    new_target_file_content = []
    target_file_content.split("\n").each do |line|
      if /#{Regexp.escape(transform_hook)}\s*$/.match?(line)

        if add_before
          new_target_file_content << "#{line} #{add_before}"
        else
          unless options[:prepend]
            new_target_file_content << line
          end
        end

        # get leading whitespace.
        line =~ /^(\s*).*#{Regexp.escape(transform_hook)}.*/
        leading_whitespace = $1
        new_target_file_content << "#{leading_whitespace}#{"  " if increase_indent}#{transformed_content}"

        new_target_file_content << "#{leading_whitespace}#{add_after}" if add_after

        if options[:prepend]
          new_target_file_content << line
        end
      else
        new_target_file_content << line
      end
    end

    puts "Updating '#{transformed_file_name}'."

    File.write(transformed_file_name, new_target_file_content.join("\n") + "\n")
  end
end

# filter out options.
argv = []
@options = {}
ARGV.each do |arg|
  if arg[0..1] == "--"
    arg = arg[2..-1]
    if arg.split("=").count > 1
      @options[arg.split("=")[0]] = arg.split("=")[1]
    else
      @options[arg] = true
    end
  else
    argv << arg
  end
end

def check_required_options_for_attributes(scaffolding_type, attributes, child, parent = nil)
  attributes.each do |attribute|
    parts = attribute.split(":")
    name = parts.shift
    type = parts.join(":")

    # extract any options they passed in with the field.
    type, attribute_options = type.scan(/^(.*)\[(.*)\]/).first || type

    # create a hash of the options.
    attribute_options = if attribute_options
      attribute_options.split(",").map do |s|
        option_name, option_value = s.split("=")
        [option_name.to_sym, option_value || true]
      end.to_h
    else
      {}
    end

    if name.match?(/_id$/) || name.match?(/_ids$/)
      attribute_options ||= {}
      unless attribute_options[:vanilla]
        name_without_id = if name.match?(/_id$/)
          name.gsub(/_id$/, "")
        elsif name.match?(/_ids$/)
          name.gsub(/_ids$/, "")
        end

        attribute_options[:class_name] ||= name_without_id.classify

        file_name = "app/models/#{attribute_options[:class_name].underscore}.rb"
        unless File.exist?(file_name)
          puts ""
          puts "Attributes that end with `_id` or `_ids` trigger awesome, powerful magic in Super Scaffolding. However, because no `#{attribute_options[:class_name]}` class was found defined in `#{file_name}`, you'll need to specify a `class_name` that exists to let us know what model class is on the other side of the association, like so:".red
          puts ""
          puts "  bin/super-scaffold #{scaffolding_type} #{child}#{" " + parent if parent.present?} #{name}:#{type}[class_name=#{name.gsub(/_ids?$/, "").classify}]".red
          puts ""
          puts "If `#{name}` is just a regular field and isn't backed by an ActiveRecord association, you can skip all this with the `[vanilla]` option, e.g.:".red
          puts ""
          puts "  bin/super-scaffold #{scaffolding_type} #{child}#{" " + parent if parent.present?} #{name}:#{type}[vanilla]".red
          puts ""
          exit
        end
      end
    end
  end
end

def show_usage
  puts ""
  puts "🚅  usage: bin/super-scaffold [type] (... | --help)"
  puts ""
  puts "Supported types of scaffolding:"
  puts ""
  puts "  crud"
  puts "  crud-field"
  puts "  join-model"
  puts "  oauth-provider"
  puts "  breadcrumbs"
  puts ""
  puts "Try \`bin/super-scaffold [type]` for usage examples.".blue
  puts ""
end

# grab the _type_ of scaffold we're doing.
scaffolding_type = argv.shift

# if we're doing the classic super scaffolding ..
if scaffolding_type == "crud"

  unless argv.count >= 3
    puts ""
    puts "🚅  usage: bin/super-scaffold crud <Model> <ParentModel[s]> <attribute:type> <attribute:type> ..."
    puts ""
    puts "E.g. a Team has many Sites with some attributes:"
    puts "  rails g model Site team:references name:string url:text"
    puts "  bin/super-scaffold crud Site Team name:string url:text"
    puts ""
    puts "E.g. a Section belongs to a Page, which belongs to a Site, which belongs to a Team:"
    puts "  rails g model Section page:references title:text body:text"
    puts "  bin/super-scaffold crud Section Page,Site,Team title:text body:text"
    puts ""
    puts "E.g. an Image belongs to either a Page or a Site:"
    puts "  Doable! See https://bit.ly/2NvO8El for a step by step guide."
    puts ""
    puts "E.g. Pages belong to a Site and are sortable via drag-and-drop:"
    puts "  rails g model Page site:references name:string path:text"
    puts "  bin/super-scaffold crud Page Site,Team name:text path:text --sortable"
    puts ""
    puts "🏆 Protip: Commit your other changes before running Super Scaffolding so it's easy to undo if you (or we) make any mistakes."
    puts "If you do that, you can reset to your last commit state by using `git checkout .` and `git clean -d -f` ."
    puts ""
    puts "Give it a shot! Let us know if you have any trouble with it! ✌️"
    puts ""
    exit
  end

  child = argv[0]
  parents = argv[1] ? argv[1].split(",") : []
  parents = parents.map(&:classify).uniq
  parent = parents.first

  unless parents.include?("Team")
    raise "Parents for #{child} should trace back to the Team model, but Team wasn't provided. Please confirm that all of the parents tracing back to the Team model are present and try again.\n" +
      "E.g.:\n" +
      "rails g model Section page:references title:text body:text\n" +
      "bin/super-scaffold crud Section Page,Site,Team title:text body:text\n"
  end

  # get all the attributes.
  attributes = argv[2..-1]

  check_required_options_for_attributes(scaffolding_type, attributes, child, parent)

  transformer = Scaffolding::Transformer.new(child, parents, @options)
  transformer.scaffold_crud(attributes)

  transformer.additional_steps.each_with_index do |additional_step, index|
    color, message = additional_step
    puts ""
    puts "#{index + 1}. #{message}".send(color)
  end
  puts ""

elsif scaffolding_type == "crud-field"

  unless argv.count >= 2
    puts ""
    puts "🚅  usage: bin/super-scaffold crud-field <Model> <attribute:type> <attribute:type> ... [options]"
    puts ""
    puts "E.g. add a description and body to Pages:"
    puts "  rails g migration add_description_etc_to_pages description:text body:text"
    puts "  bin/super-scaffold crud-field Page description:text body:text"
    puts ""
    puts "Options:"
    puts ""
    puts "  --skip-table: Only add to the new/edit form and show view."
    puts ""
    exit
  end

  # We pass this value to parents to create a new Scaffolding::Transformer because
  # we don't actually need knowledge of the parent to add the new field.
  parents = [""]
  child = argv[0]

  # get all the attributes.
  attributes = argv[1..-1]

  check_required_options_for_attributes(scaffolding_type, attributes, child)

  transformer = Scaffolding::Transformer.new(child, parents, @options)
  transformer.add_attributes_to_various_views(attributes, type: :crud_field)

  transformer.additional_steps.uniq.each_with_index do |additional_step, index|
    color, message = additional_step
    puts ""
    puts "#{index + 1}. #{message}".send(color)
  end
  puts ""

elsif scaffolding_type == "join-model"

  unless argv.count >= 3
    puts ""
    puts "🚅  usage: bin/super-scaffold join-model <JoinModel> <left_association> <right_association>"
    puts ""
    puts "E.g. Add project-specific tags to a project:"
    puts ""
    puts "  Given the following example models:".blue
    puts ""
    puts "    rails g model Project team:references name:string description:text"
    puts "    bin/super-scaffold crud Project Team name:text_field description:trix_editor"
    puts ""
    puts "    rails g model Projects::Tag team:references name:string"
    puts "    bin/super-scaffold crud Projects::Tag Team name:text_field"
    puts ""
    puts "  1️⃣  Use the standard Rails model generator to generate the join model:".blue
    puts ""
    puts "    rails g model Projects::AppliedTag project:references tag:references"
    puts ""
    puts "    👋 Don't run migrations yet! Sometimes Super Scaffolding updates them for you.".yellow
    puts ""
    puts "  2️⃣  Use `join-model` scaffolding to prepare the join model for use in `crud-field` scaffolding:".blue
    puts ""
    puts "    bin/super-scaffold join-model Projects::AppliedTag project_id[class_name=Project] tag_id[class_name=Projects::Tag]"
    puts ""
    puts "  3️⃣  Now you can use `crud-field` scaffolding to actually add the field to the form of the parent model:".blue
    puts ""
    puts "    bin/super-scaffold crud-field Project tag_ids:super_select[class_name=Projects::Tag]"
    puts ""
    puts "    👋 Heads up! There will be one follow-up step output by this command that you need to take action on."
    puts ""
    puts "  4️⃣  Now you can run your migrations.".blue
    exit
  end

  child = argv[0]
  primary_parent = argv[1].split("class_name=").last.split(",").first.split("]").first
  secondary_parent = argv[2].split("class_name=").last.split(",").first.split("]").first

  # There should only be two attributes.
  attributes = [argv[1], argv[2]]

  # Pretend we're doing a `super_select` scaffolding because it will do the correct thing.
  attributes = attributes.map { |attribute| attribute.gsub("\[", ":super_select\[") }
  attributes = attributes.map { |attribute| attribute.gsub("\]", ",required\]") }

  transformer = Scaffolding::Transformer.new(child, [primary_parent], @options)

  # We need this transformer to reflect on the class names _just_ between e.g. `Project` and `Projects::Tag`, without the join model.
  has_many_through_transformer = Scaffolding::Transformer.new(secondary_parent, [primary_parent], @options)

  # We need this transformer to reflect on the association between `Projects::Tag` and `Projects::AppliedTag` backwards.
  inverse_transformer = Scaffolding::Transformer.new(child, [secondary_parent], @options)

  # We need this transformer to reflect on the class names _just_ between e.g. `Projects::Tag` and `Project`, without the join model.
  inverse_has_many_through_transformer = Scaffolding::Transformer.new(primary_parent, [secondary_parent], @options)

  # However, for the first attribute, we actually don't need the scope validator (and can't really implement it).
  attributes[0] = attributes[0].gsub("\]", ",unscoped\]")

  has_many_through_association = has_many_through_transformer.transform_string("completely_concrete_tangible_things")
  source = transformer.transform_string("absolutely_abstract_creative_concept.valid_$HAS_MANY_THROUGH_ASSOCIATION")
  source.gsub!("$HAS_MANY_THROUGH_ASSOCIATION", has_many_through_association)

  # For the second one, we don't want users to have to define the list of valid options in the join model, so we do this:
  attributes[1] = attributes[1].gsub("\]", ",source=#{source}\]")

  # This model hasn't been crud scaffolded, so a bunch of views are skipped here, but that's OK!
  # It does what we need on the files that exist.
  transformer.add_scaffolding_hooks_to_model

  transformer.suppress_could_not_find = true
  transformer.add_attributes_to_various_views(attributes, type: :crud_field)
  transformer.suppress_could_not_find = false

  # Add the `has_many ... through:` association in both directions.
  transformer.add_has_many_through_associations(has_many_through_transformer)
  inverse_transformer.add_has_many_through_associations(inverse_has_many_through_transformer)

  additional_steps = (transformer.additional_steps + has_many_through_transformer.additional_steps + inverse_transformer.additional_steps + inverse_has_many_through_transformer.additional_steps).uniq

  additional_steps.each_with_index do |additional_step, index|
    color, message = additional_step
    puts ""
    puts "#{index + 1}. #{message}".send(color)
  end
  puts ""

elsif scaffolding_type == "breadcrumbs"

  unless argv.count == 2
    puts ""
    puts "🚅  usage: bin/super-scaffold breadcrumbs <Model> <ParentModel[s]>"
    puts ""
    puts "Heads up! You only need to use this if you generated your views before the new Bullet Train breadcrumbs implementation came into effect.".green
    puts ""
    puts "E.g. create updated breadcrumbs for Pages:"
    puts "  bin/super-scaffold breadcrumbs Page Site,Team"
    puts ""
    puts "When Super Scaffolding breadcrumbs, you have to specify the entire path of the immediate parent back to Team."
    puts ""
    exit
  end

  child = argv[0]
  parents = argv[1] ? argv[1].split(",") : []
  parents = parents.map(&:classify).uniq
  parent = parents.first

  unless parents.include?("Team")
    raise "Parents for #{child} should trace back to the Team model, but Team wasn't provided. Please confirm that all of the parents tracing back to the Team model are present and try again.\n" +
      "E.g.:\n" +
      "bin/super-scaffold breadcrumbs Page Site,Team\n"
  end

  # get all the attributes.
  transformer = Scaffolding::Transformer.new(child, parents, @options)
  transformer.scaffold_new_breadcrumbs(child, parents)

elsif scaffolding_type == "oauth-provider"

  unless argv.count >= 5
    puts ""
    puts "🚅  usage: bin/super-scaffold oauth-provider <omniauth_gem> <gems_provider_name> <our_provider_name> <PROVIDER_API_KEY_IN_ENV> <PROVIDER_API_SECRET_IN_ENV> [options]"
    puts ""
    puts "E.g. what we'd do to start Stripe off (if we didn't already do it):"
    puts "  bin/super-scaffold oauth-provider omniauth-stripe-connect stripe_connect Oauth::StripeAccount STRIPE_CLIENT_ID STRIPE_SECRET_KEY --icon=ti-money"
    puts ""
    puts "E.g. what we actually did to start Shopify off:"
    puts "  bin/super-scaffold oauth-provider omniauth-shopify-oauth2 shopify Oauth::ShopifyAccount SHOPIFY_API_KEY SHOPIFY_API_SECRET_KEY --icon=ti-shopping-cart"
    puts ""
    puts "Options:"
    puts ""
    puts "  --icon={ti-*}: Specify an icon."
    puts ""
    puts "For a list of readily available provider strategies, see https://github.com/omniauth/omniauth/wiki/List-of-Strategies ."
    puts ""
    exit
  end

  _, omniauth_gem, gems_provider_name, our_provider_name, api_key, api_secret = *ARGV

  unless match = our_provider_name.match(/Oauth::(.*)Account/)
    puts "\n🚨 Your provider name must match the pattern of `Oauth::{Name}Account`, e.g. `Oauth::StripeAccount`\n".red
    return
  end

  options = {
    omniauth_gem: omniauth_gem,
    gems_provider_name: gems_provider_name,
    our_provider_name: match[1],
    api_key: api_key,
    api_secret: api_secret
  }

  unless File.exist?(oauth_transform_string("./app/models/oauth/stripe_account.rb", options)) &&
      File.exist?(oauth_transform_string("./app/models/integrations/stripe_installation.rb", options)) &&
      File.exist?(oauth_transform_string("./app/models/webhooks/incoming/oauth/stripe_account_webhook.rb", options))
    puts ""
    puts oauth_transform_string("🚨 Before doing the actual Super Scaffolding, you'll need to generate the models like so:", options).red
    puts ""
    puts oauth_transform_string("  rails g model Oauth::StripeAccount uid:string data:jsonb user:references", options).red
    puts oauth_transform_string("  rails g model Integrations::StripeInstallation team:references oauth_stripe_account:references name:string", options).red
    puts oauth_transform_string("  rails g model Webhooks::Incoming::Oauth::StripeAccountWebhook data:jsonb processed_at:datetime verified_at:datetime oauth_stripe_account:references", options).red
    puts ""
    puts "However, don't do the `rake db:migrate` until after you re-run Super Scaffolding, as it will need to update some settings in those migrations.".red
    puts ""
    return
  end

  icon_name = nil
  if @options["icon"].present?
    icon_name = @options["icon"]
  else
    puts "OK, great! Let's do this! By default providers will appear with a dollar symbol,"
    puts "but after you hit enter I'll open a page where you can view other icon options."
    puts "When you find one you like, hover your mouse over it and then come back here and"
    puts "and enter the name of the icon you want to use."
    response = STDIN.gets.chomp
    `open http://light.pinsupreme.com/icon_fonts_themefy.html`
    puts ""
    puts "Did you find an icon you wanted to use? Enter the name here or hit enter to just"
    puts "use the dollar symbol:"
    icon_name = STDIN.gets.chomp
    puts ""
    unless icon_name.length > 0 || icon_name.downcase == "y"
      icon_name = "icon-puzzle"
    end
  end

  options[:icon] = icon_name

  [

    # User OAuth.
    "./app/models/oauth/stripe_account.rb",
    "./app/models/webhooks/incoming/oauth/stripe_account_webhook.rb",
    "./app/controllers/account/oauth/stripe_accounts_controller.rb",
    "./app/controllers/webhooks/incoming/oauth/stripe_account_webhooks_controller.rb",
    "./app/views/account/oauth/stripe_accounts",
    "./test/models/oauth/stripe_account_test.rb",
    "./test/factories/oauth/stripe_accounts.rb",
    "./config/locales/en/oauth/stripe_accounts.en.yml",
    "./app/views/devise/shared/oauth/_stripe.html.erb",

    # Team Integration.
    "./app/models/integrations/stripe_installation.rb",
    # './app/serializers/api/v1/integrations/stripe_installation_serializer.rb',
    "./app/controllers/account/integrations/stripe_installations_controller.rb",
    "./app/views/account/integrations/stripe_installations",
    "./test/models/integrations/stripe_installation_test.rb",
    "./test/factories/integrations/stripe_installations.rb",
    "./config/locales/en/integrations/stripe_installations.en.yml",

    # Webhook.
    "./app/models/webhooks/incoming/oauth/stripe_account_webhook.rb",
    "./app/controllers/webhooks/incoming/oauth/stripe_account_webhooks_controller.rb"

  ].each do |name|
    if File.directory?(name)
      oauth_scaffold_directory(name, options)
    else
      oauth_scaffold_file(name, options)
    end
  end

  oauth_scaffold_add_line_to_file("./app/views/devise/shared/_oauth.html.erb", "<%= render 'devise/shared/oauth/stripe', verb: verb if stripe_enabled? %>", "<%# 🚅 super scaffolding will insert new oauth providers above this line. %>", options, prepend: true)
  oauth_scaffold_add_line_to_file("./app/views/account/users/edit.html.erb", "<%= render 'account/oauth/stripe_accounts/index', context: @user, stripe_accounts: @user.oauth_stripe_accounts if stripe_enabled? %>", "<% # 🚅 super scaffolding will insert new oauth providers above this line. %>", options, prepend: true)
  oauth_scaffold_add_line_to_file("./config/initializers/devise.rb", "config.omniauth :stripe_connect, ENV['STRIPE_CLIENT_ID'], ENV['STRIPE_SECRET_KEY'], {\n    ## specify options for your oauth provider here, e.g.:\n    # scope: 'read_products,read_orders,write_content',\n  }\n", "# 🚅 super scaffolding will insert new oauth providers above this line.", options, prepend: true)
  oauth_scaffold_add_line_to_file("./app/controllers/account/oauth/omniauth_callbacks_controller.rb", "def stripe_connect\n    callback(\"Stripe\", team_id_from_env)\n  end\n", "# 🚅 super scaffolding will insert new oauth providers above this line.", options, prepend: true)
  oauth_scaffold_add_line_to_file("./app/models/team.rb", "has_many :integrations_stripe_installations, class_name: 'Integrations::StripeInstallation', dependent: :destroy if stripe_enabled?", "# 🚅 add oauth providers above.", options, prepend: true)
  oauth_scaffold_add_line_to_file("./app/models/user.rb", "has_many :oauth_stripe_accounts, class_name: 'Oauth::StripeAccount' if stripe_enabled?", "# 🚅 add oauth providers above.", options, prepend: true)
  oauth_scaffold_add_line_to_file("./config/locales/en/oauth.en.yml", "stripe_connect: Stripe", "# 🚅 super scaffolding will insert new oauth providers above this line.", options, prepend: true)
  oauth_scaffold_add_line_to_file("./app/views/account/shared/_menu.html.erb", "<%= render 'account/integrations/stripe_installations/menu_item' if stripe_enabled? %>", "<%# 🚅 super scaffolding will insert new oauth providers above this line. %>", options, prepend: true)
  oauth_scaffold_add_line_to_file("./config/routes.rb", "resources :stripe_account_webhooks if stripe_enabled?", "# 🚅 super scaffolding will insert new oauth provider webhooks above this line.", options, prepend: true)
  oauth_scaffold_add_line_to_file("./config/routes.rb", "resources :stripe_accounts if stripe_enabled?", "# 🚅 super scaffolding will insert new oauth providers above this line.", options, prepend: true)
  oauth_scaffold_add_line_to_file("./config/routes.rb", "resources :stripe_installations if stripe_enabled?", "# 🚅 super scaffolding will insert new integration installations above this line.", options, prepend: true)
  oauth_scaffold_add_line_to_file("./Gemfile", "gem 'omniauth-stripe-connect'", "# 🚅 super scaffolding will insert new oauth providers above this line.", options, prepend: true)
  oauth_scaffold_add_line_to_file("./lib/bullet_train.rb", "def stripe_enabled?\n  ENV['STRIPE_CLIENT_ID'].present? && ENV['STRIPE_SECRET_KEY'].present?\nend\n", "# 🚅 super scaffolding will insert new oauth providers above this line.", options, prepend: true)
  oauth_scaffold_add_line_to_file("./lib/bullet_train.rb", "stripe_enabled?,", "# 🚅 super scaffolding will insert new oauth provider checks above this line.", options, prepend: true)
  oauth_scaffold_add_line_to_file("./app/models/ability.rb", "if stripe_enabled?
        can [:read, :create, :destroy], Oauth::StripeAccount, user_id: user.id
        can :manage, Integrations::StripeInstallation, team_id: user.team_ids
        can :destroy, Integrations::StripeInstallation, oauth_stripe_account: {user_id: user.id}
      end
", "# 🚅 super scaffolding will insert any new oauth providers above.", options, prepend: true)

  # find the database migration that defines this relationship.
  migration_file_name = `grep "create_table #{oauth_transform_string(":oauth_stripe_accounts", options)}" db/migrate/*`.split(":").first
  legacy_replace_in_file(migration_file_name, "null: false", "null: true")

  migration_file_name = `grep "create_table #{oauth_transform_string(":integrations_stripe_installations", options)}" db/migrate/*`.split(":").first
  legacy_replace_in_file(migration_file_name,
    oauth_transform_string("t.references :oauth_stripe_account, null: false, foreign_key: true", options),
    oauth_transform_string('t.references :oauth_stripe_account, null: false, foreign_key: true, index: {name: "index_stripe_installations_on_oauth_stripe_account_id"}', options))

  migration_file_name = `grep "create_table #{oauth_transform_string(":webhooks_incoming_oauth_stripe_account_webhooks", options)}" db/migrate/*`.split(":").first
  legacy_replace_in_file(migration_file_name, "null: false", "null: true")
  legacy_replace_in_file(migration_file_name, "foreign_key: true", 'foreign_key: true, index: {name: "index_stripe_webhooks_on_oauth_stripe_account_id"}')

  puts ""
  puts "🎉"
  puts ""
  puts "You'll probably need to `bundle install`.".green
  puts ""
  puts "If the OAuth provider asks you for some whitelisted callback URLs, the URL structure for those is as so:"
  puts ""
  path = "users/auth/stripe_connect/callback"
  puts oauth_transform_string("  https://yourdomain.co/#{path}", options)
  puts oauth_transform_string("  https://yourtunnel.ngrok.io/#{path}", options)
  puts oauth_transform_string("  http://localhost:3000/#{path}", options)
  puts ""
  puts "If you're able to specify an endpoint to receive webhooks from this provider, use this URL:"
  puts ""
  path = "webhooks/incoming/oauth/stripe_account_webhooks"
  puts oauth_transform_string("  https://yourdomain.co/#{path}", options)
  puts oauth_transform_string("  https://yourtunnel.ngrok.io/#{path}", options)
  puts oauth_transform_string("  http://localhost:3000/#{path}", options)
  puts ""
  puts ""
  puts "If you'd like to edit how your Bullet Train application refers to this provider, just edit the locale file at `config/locales/en/oauth.en.yml`."
  puts ""
  puts "And finally, if you need to specify any custom authorizations or options for your OAuth integration with this provider, you can configure those in `config/initializers/devise.rb`."
  puts ""

elsif argv.count > 1

  puts ""
  puts "👋"
  puts "The command line options for Super Scaffolding have changed slightly:".yellow
  puts "To use the original Super Scaffolding that you know and love, use the `crud` option.".yellow
  show_usage

else
  if ARGV.first.present?
    puts ""
    puts "Invalid scaffolding type \"#{ARGV.first}\".".red
  end

  show_usage
end