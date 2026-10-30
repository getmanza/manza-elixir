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

  # How long a writer waits for another one to finish.
  @lock_timeout_ms 10_000

  @doc """
  Records `entry` under `client_reference`. Writers take turns on a separate
  lock file (`<ledger>.lock`, created exclusively); each writes the new ledger
  to a temporary file and renames it over the old one: a reader sees the old
  or the new ledger, never a half-written one, and a crash mid-write leaves
  the old ledger intact.
  """
  def record(path, client_reference, entry) do
    with_lock(path, fn ->
      entries = path |> read_entries() |> Map.put(client_reference, entry)
      tmp = "#{path}.#{System.pid()}.tmp"
      # Owner-only before the entries go in.
      File.write!(tmp, "")
      File.chmod!(tmp, 0o600)
      File.write!(tmp, Jason.encode_to_iodata!(entries, pretty: true))
      File.rename!(tmp, path)
    end)

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

  defp with_lock(path, fun) do
    lock = path <> ".lock"
    acquire(lock, System.monotonic_time(:millisecond) + @lock_timeout_ms)

    try do
      fun.()
    after
      File.rm(lock)
    end
  end

  defp acquire(lock, deadline) do
    case File.open(lock, [:write, :exclusive]) do
      {:ok, io} ->
        File.close(io)

      {:error, :eexist} ->
        if System.monotonic_time(:millisecond) >= deadline do
          raise "#{lock} is held: another mix create_transfer is writing, or one was killed " <>
                  "mid-write; remove the file if none is running"
        end

        Process.sleep(20)
        acquire(lock, deadline)
    end
  end
end
