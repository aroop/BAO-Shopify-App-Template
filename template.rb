=begin
Author: By Association Only
Author URI: https://byassociationonly.com
Instructions: $ rails new myapp -d postgresql -m https://raw.githubusercontent.com/baoagency/BAO-Shopify-App-Template/master/template.rb
=end

APPLICATION_AFTER = "config.load_defaults 6.1"

NGROK_DOMAIN = ask('What will the NGROK domain be?')
NGROK_WEBPACK_DOMAIN = ask('What will the Webpack NGROK domain be?')
SHOPIFY_API_KEY = ask("What is the App's API key?")
SHOPIFY_API_SECRET = ask("What is the App's API secret?")
SHOPIFY_SCOPES = ask("What scopes does the app want?")
SHOPIFY_SCOPES = 'write_products' unless SHOPIFY_SCOPES

# Add this template directory to source_paths so that Thor actions like
# copy_file and template resolve against our source files. If this file was
# invoked remotely via HTTP, that means the files are not present locally.
# In that case, use `git clone` to download them to a local temporary dir.
require "fileutils"
require "shellwords"

def add_template_repository_to_source_path
  if __FILE__ =~ %r{\Ahttps?://}
    require "tmpdir"
    source_paths.unshift(tempdir = Dir.mktmpdir("rails-template-"))
    at_exit { FileUtils.remove_entry(tempdir) }
    git clone: [
      "--quiet",
      "https://github.com/baoagency/BAO-Shopify-App-Template.git",
      tempdir
    ].map(&:shellescape).join(" ")

    if (branch = __FILE__[%r{rails-template/(.+)/template.rb}, 1])
      Dir.chdir(tempdir) { git checkout: branch }
    end
  else
    source_paths.unshift(File.dirname(__FILE__))
  end
end

def add_gems
  gem 'shopify_app', '~> 18.0.1'
  gem 'hotwire-rails'
  gem 'rack-cors', :require => 'rack/cors'
  gem "view_component", require: "view_component/engine"

  gem "annotate", group: [:development]
end

def initial_setup
  insert_into_file "config/application.rb",
    "config.generators.stylesheets = false\n",
    after: APPLICATION_AFTER
  insert_into_file "config/application.rb",
    "    config.generators.system_tests = false\n",
    after: APPLICATION_AFTER
  insert_into_file "config/environments/development.rb",
    "\n    config.hosts << '#{NGROK_DOMAIN}'",
    after: "config.file_watcher = ActiveSupport::EventedFileUpdateChecker"

  generate "annotate:install"
end

def initialise_shopify_app
  template "example.env.tt"
  template "example.env.tt", ".env"
  template "example.env.tt", ".env.example"

  gsub_file '.env', /SHOPIFY_API_KEY=/, "SHOPIFY_API_KEY=#{SHOPIFY_API_KEY}"
  gsub_file '.env', /SHOPIFY_API_SECRET=/, "SHOPIFY_API_SECRET=#{SHOPIFY_API_SECRET}"
  gsub_file '.env', /SCOPES=/, "SCOPES=#{SHOPIFY_SCOPES}"
  gsub_file '.env', /NGROK_WEBPACK_TUNNEL=/, "NGROK_WEBPACK_TUNNEL=#{NGROK_WEBPACK_DOMAIN}"

  generate "shopify_app"
end

def initialise_hotwire
  rails_command 'hotwire:install'

  run 'bundle install'
end

def add_cors
  cors_content = <<-RUBY
    config.middleware.insert_before 0, Rack::Cors do
      allow do
        origins '*'
        resource '*', headers: :any, methods: [:get, :post, :patch, :options, :delete]
      end
    end
  RUBY

  insert_into_file "config/application.rb",
    "#{cors_content}\n",
    after: APPLICATION_AFTER
end

def setup_webpacker
  run "yarn add dotenv"

  webpacker_content = <<-JAVASCRIPT
    const dotenv = require('dotenv')
    dotenv.config({ path: '.env', silent: true })
    
    environment.config.merge({
      devServer: {
        public: process.env.NGROK_WEBPACK_TUNNEL,
      },
    })
  JAVASCRIPT

  gsub_file 'config/webpacker.yml', /additional_paths: \[\]/, "additional_paths: ['app/components']"

  inject_into_file './config/webpack/development.js', "\n#{webpacker_content}", after: "const environment = require('./environment')"
end

def setup_polaris
  run "yarn add @shopify/app-bridge @shopify/app-bridge-utils @shopify/polaris"
end

def add_js_linting
  copy_file ".eslintrc.js"
  run "yarn add -D @by-association-only/eslint-config-unisian eslint"
  package_json_content = <<-PACKAGE
  "scripts": {
    "lint:js": "eslint 'app/javascript/**/*.js' --fix"
  },
  "husky": {
    "hooks": {
      "pre-commit": "lint-staged"
    }
  },
  "lint-staged": {
    "*.js": [
      "prettier-standard",
      "eslint --fix",
      "git add"
    ]
  },
  PACKAGE

  inject_into_file "./package.json",
    "#{package_json_content}",
    before: '  "dependencies": {'

  run "yarn add -D husky lint-staged"
end

def add_foreman
  copy_file "Procfile"
  copy_file "Procfile.dev"
end

def copy_templates
  directory "app", force: true
  directory "config", force: true
end

add_template_repository_to_source_path
add_gems

after_bundle do
  initial_setup
  initialise_shopify_app
  initialise_hotwire
  add_js_linting
  add_foreman
  add_cors
  setup_webpacker
  setup_polaris

  copy_templates

  rails_command "db:create"
  rails_command "db:migrate"

  git :init
  git add: "."
  git commit: %Q{ -m "Initial commit" }

  say
  say "Kickoff app successfully created! 👍", :green
  say
  say "Switch to your app by running:"
  say "$ cd #{app_name}", :yellow
  say
  say "Then run:"
  say "$ foreman start -f Procfile.dev", :green
end
