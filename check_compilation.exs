# Manually load and parse files to check for compilation errors since mix is unavailable

files = [
  "governance_core/lib/governance_core/protocols/fuzzer.ex",
  "governance_core/lib/governance_core/ax_audit.ex",
  "governance_core/lib/governance_core/monitoring/skill_tracker.ex",
  "governance_core/lib/governance_core/monitoring/resource_watchdog.ex",
  "governance_core/lib/governance_core/security/nightly_audit.ex",
  "governance_core/lib/governance_core/application.ex"
]

Enum.each(files, fn file ->
  IO.puts("Compiling: #{file}")
  try do
    Code.compile_file(file)
    IO.puts("✓ Success")
  rescue
    e ->
      IO.puts("✗ Error compiling #{file}: #{inspect(e)}")
  end
end)
