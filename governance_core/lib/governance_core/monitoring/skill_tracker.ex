defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  GenServer that continuously generates standardized SKILL.md documentation
  for all project modules to ensure "Agent-Friendly" standards.
  Chunked to adhere to a strict 1024 character limit per file.
  """
  use GenServer
  require Logger

  @interval 5 * 60 * 1000
  @char_limit 1024

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_update()
    {:ok, state}
  end

  def handle_info(:update, state) do
    Logger.info("SkillTracker starting SKILL.md generation...")
    generate_skill_docs()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update, @interval)
  end

  defp generate_skill_docs do
    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        chunks = chunk_modules(modules)
        write_chunks(chunks)
      :undefined ->
        Logger.error("SkillTracker couldn't find :governance_core modules.")
    end
  end

  defp chunk_modules(modules) do
    Enum.reduce(modules, [{[], 0}], fn mod, chunks ->
      # Get the last active chunk
      [{current_mods, current_len} | rest_chunks] = chunks

      mod_yaml = generate_yaml_for_module(mod)
      mod_len = String.length(mod_yaml)

      if current_len + mod_len > @char_limit and current_len > 0 do
        # Start a new chunk
        [{[mod], mod_len}, {current_mods, current_len} | rest_chunks]
      else
        # Add to current chunk
        [{current_mods ++ [mod], current_len + mod_len} | rest_chunks]
      end
    end)
    |> Enum.reverse()
    |> Enum.map(fn {mods, _len} ->
      yaml_content = Enum.map_join(mods, "\n", &generate_yaml_for_module/1)
      "---\nversion: 1.0\nskills:\n" <> yaml_content
    end)
  end

  defp generate_yaml_for_module(mod) do
    mod_name = inspect(mod)
    docs = get_module_doc(mod)

    # Properly indent multiline YAML text
    indented_docs =
      docs
      |> String.split("\n")
      |> Enum.map_join("\n", fn line -> "      " <> line end)

    """
      - name: #{mod_name}
        description: |
    #{indented_docs}
    """
  end

  defp get_module_doc(mod) do
    case Code.fetch_docs(mod) do
      {:docs_v1, _, :elixir, "text/markdown", %{"en" => doc}, _, _} -> doc
      _ -> "No documentation provided."
    end
  end

  defp write_chunks(chunks) do
    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)

    Enum.with_index(chunks, fn chunk, index ->
      filename = if index == 0, do: "SKILL.md", else: "SKILL_#{index + 1}.md"
      filepath = Path.join(priv_dir, filename)

      case File.write(filepath, chunk) do
        :ok -> Logger.info("Wrote #{filename}")
        {:error, reason} -> Logger.error("Failed to write #{filename}: #{inspect(reason)}")
      end
    end)
  end
end
