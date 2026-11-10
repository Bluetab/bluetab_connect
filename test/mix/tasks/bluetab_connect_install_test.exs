defmodule Mix.Tasks.BluetabConnect.InstallTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  defp install(connectors, igniter \\ nil) do
    (igniter || phx_test_project(app_name: :demo))
    |> Igniter.compose_task("bluetab_connect.install", connectors)
    |> apply_igniter!()
  end

  defp content(igniter, path) do
    igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)
  end

  defp count(text, fragment), do: text |> String.split(fragment) |> length() |> Kernel.-(1)

  describe "markt_rest" do
    test "reads the Markt URL and API key at runtime" do
      igniter = install(["markt_rest"])
      runtime = content(igniter, "config/runtime.exs")

      assert runtime =~ ~s|config :demo, :markt,|
      assert runtime =~ ~s|base_url: System.fetch_env!("MARKT_API_URL")|
      assert runtime =~ ~s|api_key: System.fetch_env!("MARKT_API_KEY")|
    end

    test "keeps the config out of the test environment" do
      runtime = "markt_rest" |> List.wrap() |> install() |> content("config/runtime.exs")

      [_before, guarded] = String.split(runtime, "if config_env() != :test do", parts: 2)
      assert guarded =~ ":markt,"
    end

    test "supervises the client only when it is configured" do
      application = ["markt_rest"] |> install() |> content("lib/demo/application.ex")

      assert application =~
               "maybe_child(BluetabConnect.Markt.Rest, Application.get_env(:demo, :markt))"

      assert application =~ "defp maybe_child(_module, nil), do: []"
    end

    test "chains with the other connectors" do
      application =
        ["tempo_rest", "markt_rest"] |> install() |> content("lib/demo/application.ex")

      assert application =~
               "maybe_child(BluetabConnect.Tempo.Rest, Application.get_env(:demo, :tempo)) ++"

      assert application =~
               "maybe_child(BluetabConnect.Markt.Rest, Application.get_env(:demo, :markt))"
    end

    test "does nothing the second time" do
      igniter = install(["markt_rest"])
      again = install(["markt_rest"], igniter)

      assert count(content(again, "config/runtime.exs"), "config :demo, :markt,") == 1
      assert count(content(again, "lib/demo/application.ex"), "BluetabConnect.Markt.Rest") == 1
    end

    test "tells which environment variables to set" do
      igniter =
        phx_test_project(app_name: :demo)
        |> Igniter.compose_task("bluetab_connect.install", ["markt_rest"])

      notice = Enum.join(igniter.notices, "\n")
      assert notice =~ "MARKT_API_URL"
      assert notice =~ "MARKT_API_KEY"
      assert notice =~ "send_email"
    end
  end

  test "an unknown connector lists markt_rest among the valid ones" do
    igniter =
      phx_test_project(app_name: :demo)
      |> Igniter.compose_task("bluetab_connect.install", ["nope"])

    assert Enum.any?(igniter.issues, &(&1 =~ "markt_rest"))
  end
end
