defmodule TransferAuthorizer.Ledger do
  @moduledoc """
  Your own record of the transfers you created, keyed by the
  `client_reference` you generated. A JSON file, so the creator
  (`mix create_transfer`) and the authorizer (`mix authorizer`) can run as
  two processes. Swap it for your database in production.

      %{"po_8812" => %{"payment_id" => "...", "amount" => "2500.0",
                       "currency_code" => "MAD", "account_id" => "...",
                       "payee" => "ext:..."}}
  """

  @doc """
  Records `entry` under `client_reference`. Writes the new ledger to a
  temporary file and renames it over the old one: a reader sees the old or the
  new ledger, never a half-written one, and a crash mid-write leaves the old
  ledger intact. One creator at a time: two concurrent writers can lose an
  entry (the authorizer then declines that transfer).
  """
  def record(path, client_reference, entry) do
    entries = path |> read_entries() |> Map.put(client_reference, entry)
    tmp = "#{path}.#{System.pid()}.tmp"
    # Owner-only before the entries go in.
    File.write!(tmp, "")
    File.chmod!(tmp, 0o600)
    File.write!(tmp, Jason.encode_to_iodata!(entries, pretty: true))
    File.rename!(tmp, path)
    entry
  end

  @doc "The entry for `client_reference`, or `nil`."
  def find(path, client_reference) do
    path |> read_entries() |> Map.get(client_reference)
  end

  defp read_entries(path) do
    case File.read(path) do
      {:ok, json} -> if String.trim(json) == "", do: %{}, else: Jason.decode!(json)
      {:error, :enoent} -> %{}
    end
  end
end
