defmodule UcxChat.Mixfile do
  use Mix.Project

  def project do
    [
      app: :ucxChat,
      version: "0.0.1",
      elixir: "~> 1.4",
      elixirc_paths: elixirc_paths(Mix.env),
      compilers: [:phoenix, :gettext] ++ Mix.compilers,
      start_permanent: Mix.env == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {UcxChat.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_),     do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.3.0"},
      {:phoenix_pubsub, "~> 1.0"},
      {:phoenix_ecto, "~> 3.2"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 2.10"},
      {:phoenix_live_reload, "~> 1.0", only: :dev},
      {:gettext, "~> 0.11"},
      {:plug_cowboy, "~> 1.0"},
      {:mariaex, ">= 0.0.0"},
      {:coherence, github: "smpallen99/coherence"},
      # {:coherence, path: "../coherence_channels"},
      {:ex_machina, "~> 1.0.2", only: :test},
      {:excoveralls, "~> 0.5.1", only: :test, app: false},
      {:faker_elixir_octopus, "~> 0.12.0", only: [:dev, :test]},
      {:hound, "~> 1.0"},
      {:distillery, "~> 1.2"},
      {:hackney, "~> 1.7.1", override: true},
      {:syslog, github: "smpallen99/syslog"},
      {:link_preview, "~> 1.0.0"},
      {:html_entities, "~> 0.2"},
      {:mogrify, "~> 0.4.0"},
      {:tempfile, "~> 0.1.0"},
      # {:auto_linker, path: "../auto_linker"},
      {:auto_linker, "~> 0.1"},
      {:arc_ecto, "~> 0.6.0"},
      # {:auto_linker, path: "../auto_linker"},
      {:ex_doc, "~> 0.15", only: :dev},
      {:earmark, "~> 1.2"},
      {:hedwig, "~> 1.0"},
      {:hedwig_simple_responders, "~> 0.1.2"},
      {:httpoison, "~> 0.11", override: true},
      {:poison, "~> 2.0", override: true},
      {:cowboy, "~> 1.0", override: true},
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to create, migrate and run the seeds file at once:
  #
  #     $ mix ecto.setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      "test": ["ecto.create --quiet", "ecto.migrate", "test"]
    ]
  end
end
