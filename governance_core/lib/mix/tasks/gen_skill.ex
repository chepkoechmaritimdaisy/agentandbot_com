defmodule Mix.Tasks.GenSkill do
  @moduledoc """
  Generates SKILL.md documentation for GovernanceCore Tools.
  """
  use Mix.Task

  @shortdoc "Generates SKILL.md documentation"

  def run(_args) do
    Mix.Task.run("compile")

    # Assuming tools are under GovernanceCore.Tools namespace
    # Since we can't easily list all modules in Elixir without complex scanning,
    # we'll assume a specific directory structure or a list of tools.
    # A better approach for discovery is scanning the `ebin` directory,
    # but for simplicity, let's scan the source directory for file names.

    tool_files = Path.wildcard("lib/governance_core/tools/*.ex")

    docs = Enum.map(tool_files, fn file ->
      module_name =
        file
        |> Path.basename(".ex")
        |> Macro.camelize()
        |> then(&Module.concat([GovernanceCore, Tools, &1]))

      case Code.ensure_loaded(module_name) do
        {:module, _} ->
          get_tool_doc(module_name)
        {:error, reason} ->
          Mix.shell().error("Could not load module #{inspect(module_name)}: #{inspect(reason)}")
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)

    content = Enum.join(docs, "\n\n---\n\n")

    File.write!("SKILL.md", content)
    Mix.shell().info("Generated SKILL.md with #{length(docs)} tools.")
  end

  defp get_tool_doc(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, :elixir, "text/markdown", %{"en" => doc}, _, _} ->
        format_skill(module, doc)
      _ ->
        nil
    end
  end

  defp format_skill(module, doc) do
    name = module |> Atom.to_string() |> String.split(".") |> List.last()

    # Simple YAML frontmatter
    frontmatter = """
    ---
    name: #{name}
    description: #{extract_description(doc)}
    ---
    """

    full_text = frontmatter <> "\n" <> doc

    if String.length(full_text) > 1024 do
      String.slice(full_text, 0, 1021) <> "..."
    else
      full_text
    end
  end

  defp extract_description(doc) do
    doc
    |> String.split("\n")
    |> List.first()
    |> String.slice(0, 100)
    |> String.trim()
  end
end
