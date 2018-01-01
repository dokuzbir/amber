require "cli"
require "yaml"
require "colorize"
require "spinner"

module Amber::CLI
  class MainCommand < ::Cli::Supercommand
    command "d", aliased: "deploy"

    class Deploy < Command
      command_name "deploy"
      property server_name : String?
      property project_name : String?

      class Help
        header "Provisions server and deploys project."
        caption "# Provisions server and deploys project."
      end

      class Options
        bool "--init"
        arg "server_suffix", desc: "# Name of server.", default: "production"
        string ["-s", "--service"], desc: "# Deploy to cloud service: digitalocean | heroku | aws | azure", default: "digitalocean"
        string ["-k", "--key"], desc: "# API Key for service"
        string ["-t", "--tag"], desc: "# Tag to use. Overrides branch."
        string ["-b", "--branch"], desc: "# Branch to use. Default master.", default: "master"
        string ["-e", "--environment"], desc: "# Environment to deploy as.", default: "production"
        bool "--no-color", desc: "# Disable colored output", default: false
        bool "--remote-database", desc: "# Use Remote Database or Docker Image on same server.", default: false
        help
      end

      def run
        CLI.toggle_colors(options.no_color?)
        (spinner = Spin.new(0.1, Spinner::Charset[:arrow2].map { |c| c.colorize(:light_green).to_s })).start
        shard = YAML.parse(File.read("./shard.yml"))
        @project_name = shard["name"].to_s
        @server_name = "#{project_name}-#{args.server_suffix}".gsub(/[^\w\d\-]|_/, "")
        if options.init?
          provision
        else
          deploy
        end
        spinner.stop
      rescue e
        exit! e.message, error: true
      end

      private def provision
        puts "Provisioning server #{server_name}."
        create_cloud_server
        create_swapfile
        create_deploy_keys
        clone_project
        setup_project
        deploy_project
        display_helper_links
      end

      private def deploy
        puts "Deploying latest changes to server #{server_name}"
        update_project
        deploy_project
        display_helper_links
      end

      private def display_helper_links
        ip = `docker-machine ip #{server_name}`.strip
        puts "ssh root@#{ip} -i ~/.docker/machine/machines/#{server_name}/id_rsa"
        puts "open http://#{ip}"
      end

      private def create_deploy_keys
        remote_cmd(%Q(bash -c "echo | ssh-keygen -q -N '' -t rsa -b 4096 -C 'deploy@#{project_name}'"))
        puts "\nPlease add this to your projects deploy keys on github or gitlab:"
        puts remote_cmd("tail .ssh/id_rsa.pub")
        puts "\n"
      end

      private def getsecret(prompt : (String | Nil) = nil)
        puts "#{prompt}"
        password = STDIN.noecho(&.gets).try(&.chomp)
        password
      end

      private def create_cloud_server
        puts "Deploying #{server_name}"
        puts "Creating docker machine: #{server_name}"
        puts "Enter your write enabled Digital Ocean API KEY or create on with the link below."
        puts "https://cloud.digitalocean.com/settings/api/tokens/new"
        do_token = options.key? || getsecret("DigitalOcean Token")
        `docker-machine create #{server_name} --driver=digitalocean --digitalocean-access-token=#{do_token}`
        puts "Done creating machine!"
      end

      private def remote_cmd(cmd)
        `docker-machine ssh #{server_name} #{cmd}`
      end

      private def create_swapfile
        cmds = ["dd if=/dev/zero of=/swapfile bs=2k count=1024k"]
        cmds << "mkswap /swapfile"
        cmds << "chmod 600 /swapfile"
        cmds << "swapon /swapfile"
        remote_cmd(%Q("#{cmds.join(" && ")}"))
        remote_cmd("bash -c \"echo '/swapfile       none    swap    sw      0       0 ' >> /etc/fstab\"")
      end

      private def clone_project
        remote_cmd("apt-get install git")
        puts "Please enter repo to deploy from:"
        puts "Example: git@github.com/you/project.git"
        repo = gets
        remote_cmd(%Q("ssh-keyscan github.com >> ~/.ssh/known_hosts"))
        remote_cmd(%Q(bash -c "yes yes | git clone #{repo} amberproject"))
        remote_cmd(%Q(echo "#{Support::FileEncryptor.encryption_key}" > amberproject/.encryption_key))
      end

      private def setup_project
        puts "Deploying project..."
        parallel(
          remote_cmd("docker network create --driver bridge ambernet"),
          remote_cmd("docker build -t amberimage -f amberproject/Dockerfile amberproject")
        )

        amber_env = options.environment

        if options.remote_database?
          remote_cmd("docker run -it --name amberweb -v /root/amberproject:/app -p 80:3000 --network=ambernet -e #{amber_env} -d amberimage")
        else
          parallel(
            remote_cmd("docker run -it --name amberdb -v /root/db_volume:/var/lib/postgresql/data --network=ambernet -e POSTGRES_USER=admin -e POSTGRES_PASSWORD=password -e POSTGRES_DB=crystaldo_development -d postgres"),
            remote_cmd("docker run -it --name amberweb -v /root/amberproject:/app -p 80:3000 --network=ambernet -e #{amber_env} -e DATABASE_URL=postgres://admin:password@amberdb:5432/crystaldo_development -d amberimage")
          )
        end
      end

      private def update_project
        checkout_string = options.tag? ? "tags/#{options.tag?}" : options.branch
        remote_cmd %Q(bash -c "cd amberproject && git pull && git checkout #{checkout_string}")
      end

      private def deploy_project
        setup_project if remote_cmd("docker ps").count("\n") < 3
        remote_cmd "docker exec -i amberweb crystal deps update"
        remote_cmd "docker exec -i amberweb amber db migrate"
        remote_cmd "docker exec -i amberweb crystal build src/#{project_name}.cr"
        remote_cmd "docker exec -i amberweb killall #{project_name}"
        remote_cmd "docker exec -id amberweb ./#{project_name}"
      end

      private def stop_and_remove
        cmds = ["docker rm -rf amberweb"]
        cmds << "docker rm -rf amberdb"
        remote_cmd(%Q(bash -c "#{cmds.join(" && ")}"))
      end

      private def update_project
        remote_cmd(%Q("cd amberproject && git pull"))
      end

      private def server_name
        @server_name.colorize(:green)
      end
    end
  end
end
