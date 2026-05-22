defmodule TestUMPFuzz do
  def run do
    Enum.each(1..10, fn _ ->
      payload = :crypto.strong_rand_bytes(10)
      GovernanceCore.Protocols.UMP.Parser.parse_frame(payload)
      |> IO.inspect()
    end)
  end
end
