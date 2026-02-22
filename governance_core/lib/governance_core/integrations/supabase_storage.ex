defmodule GovernanceCore.Integrations.SupabaseStorage do
  @moduledoc """
  Manages file uploads to Supabase Storage (e.g., invoices).
  Uses `Req` to interact with the Supabase Storage API.
  """
  require Logger

  @bucket "invoices"

  def upload_invoice(filename, file_content) do
    config = Application.get_env(:governance_core, :supabase)
    url = "#{config[:url]}/storage/v1/object/#{@bucket}/#{filename}"

    headers = [
      {"Authorization", "Bearer #{config[:key]}"},
      {"Content-Type", "application/pdf"} # Assume PDF for invoices
    ]

    case Req.post(url, body: file_content, headers: headers) do
      {:ok, %{status: 200}} ->
        {:ok, filename}
      {:ok, %{status: status, body: body}} ->
        Logger.error("Supabase Upload Failed: #{status} - #{inspect(body)}")
        {:error, :upload_failed}
      {:error, reason} ->
        Logger.error("Supabase Connection Error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def get_public_url(filename) do
    config = Application.get_env(:governance_core, :supabase)
    "#{config[:url]}/storage/v1/object/public/#{@bucket}/#{filename}"
  end
end
