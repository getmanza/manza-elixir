defmodule TransferAuthorizer.LedgerTest do
  use ExUnit.Case, async: true

  alias TransferAuthorizer.Ledger

  @moduletag :tmp_dir

  test "finds nothing in a ledger that does not exist yet", %{tmp_dir: dir} do
    assert Ledger.find(Path.join(dir, "ledger.json"), "po_1") == nil
  end

  test "records entries by client_reference and keeps the others", %{tmp_dir: dir} do
    path = Path.join(dir, "ledger.json")

    Ledger.record(path, "po_1", %{"payment_id" => "p1", "amount" => "10.0"})
    Ledger.record(path, "po_2", %{"payment_id" => "p2", "amount" => "20.0"})

    assert Ledger.find(path, "po_1") == %{"payment_id" => "p1", "amount" => "10.0"}
    assert Ledger.find(path, "po_2")["payment_id"] == "p2"
    assert Path.wildcard(Path.join(dir, "*.tmp")) == []
  end
end
