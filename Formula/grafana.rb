class Grafana < Formula
  desc "Gorgeous metric visualizations and dashboards for timeseries databases."
  homepage "https://grafana.com"
  url "https://github.com/grafana/grafana/archive/v4.3.2.tar.gz"
  sha256 "02753931d9abb5d94e0695fdb44f5ede0a537cad57a7d60f44125056c04129ab"

  head "https://github.com/grafana/grafana.git"

  bottle do
    cellar :any_skip_relocation
    sha256 "72dfd565d092dc4637ce7da475210e52a06322550876d5f7670ae52c3118bbc3" => :sierra
    sha256 "8cf8027f5bf26fcecd16a1ee7965eb7f15e331531dcbdf8e14f06e9179f7f192" => :el_capitan
    sha256 "867ba9f2cbf689b329f2b0d992306667a75024863e1888d850107d2dfe45082e" => :yosemite
  end

  depends_on "go" => :build
  depends_on "node" => :build
  depends_on "yarn" => :build

  def install
    ENV["GOPATH"] = buildpath
    grafana_path = buildpath/"src/github.com/grafana/grafana"
    grafana_path.install buildpath.children

    cd grafana_path do
      system "go", "run", "build.go", "build"
      system "yarn", "install"

      args = ["build"]
      # Avoid PhantomJS error "unrecognized selector sent to instance"
      args << "--force" unless build.bottle?
      system "node_modules/grunt-cli/bin/grunt", *args

      bin.install "bin/grafana-cli"
      bin.install "bin/grafana-server"
      (etc/"grafana").mkpath
      cp("conf/sample.ini", "conf/grafana.ini.example")
      etc.install "conf/sample.ini" => "grafana/grafana.ini"
      etc.install "conf/grafana.ini.example" => "grafana/grafana.ini.example"
      pkgshare.install "conf", "vendor"
      pkgshare.install "public_gen" => "public"
    end
  end

  def post_install
    (var/"log/grafana").mkpath
    (var/"lib/grafana/plugins").mkpath
  end

  plist_options :manual => "grafana-server --config=#{HOMEBREW_PREFIX}/etc/grafana/grafana.ini --homepath #{HOMEBREW_PREFIX}/share/grafana cfg:default.paths.logs=#{HOMEBREW_PREFIX}/var/log/grafana cfg:default.paths.data=#{HOMEBREW_PREFIX}/var/lib/grafana cfg:default.paths.plugins=#{HOMEBREW_PREFIX}/var/lib/grafana/plugins"

  def plist; <<-EOS.undent
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
      <dict>
        <key>KeepAlive</key>
        <dict>
          <key>SuccessfulExit</key>
          <false/>
        </dict>
        <key>Label</key>
        <string>#{plist_name}</string>
        <key>ProgramArguments</key>
        <array>
          <string>#{opt_bin}/grafana-server</string>
          <string>--config</string>
          <string>#{etc}/grafana/grafana.ini</string>
          <string>--homepath</string>
          <string>#{opt_pkgshare}</string>
          <string>cfg:default.paths.logs=#{var}/log/grafana</string>
          <string>cfg:default.paths.data=#{var}/lib/grafana</string>
          <string>cfg:default.paths.plugins=#{var}/lib/grafana/plugins</string>
        </array>
        <key>RunAtLoad</key>
        <true/>
        <key>WorkingDirectory</key>
        <string>#{var}/lib/grafana</string>
        <key>StandardErrorPath</key>
        <string>#{var}/log/grafana/grafana-stderr.log</string>
        <key>StandardOutPath</key>
        <string>#{var}/log/grafana/grafana-stdout.log</string>
        <key>SoftResourceLimits</key>
        <dict>
          <key>NumberOfFiles</key>
          <integer>10240</integer>
        </dict>
      </dict>
    </plist>
   EOS
  end

  test do
    require "pty"
    require "timeout"

    # first test
    system bin/"grafana-server", "-v"

    # avoid stepping on anything that may be present in this directory
    tdir = File.join(Dir.pwd, "grafana-test")
    Dir.mkdir(tdir)
    logdir = File.join(tdir, "log")
    datadir = File.join(tdir, "data")
    plugdir = File.join(tdir, "plugins")
    [logdir, datadir, plugdir].each do |d|
      Dir.mkdir(d)
    end
    Dir.chdir(pkgshare)

    res = PTY.spawn(bin/"grafana-server", "cfg:default.paths.logs=#{logdir}", "cfg:default.paths.data=#{datadir}", "cfg:default.paths.plugins=#{plugdir}", "cfg:default.server.http_port=50100")
    r = res[0]
    w = res[1]
    pid = res[2]

    listening = Timeout.timeout(5) do
      li = false
      r.each do |l|
        if l =~ /Initializing HTTP Server/
          li = true
          break
        end
      end
      li
    end

    Process.kill("TERM", pid)
    w.close
    r.close
    listening
  end
end
