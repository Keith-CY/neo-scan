defmodule Neoscan.Addresses do
  @moduledoc false
  @moduledoc """
  The boundary for the Addresses system.
  """

  import Ecto.Query, warn: false
  alias Neoscan.Repo
  alias Neoscan.Addresses.Address
  alias Neoscan.Addresses.History
  alias Neoscan.Addresses.Claim
  alias Neoscan.Vouts
  alias Ecto.Multi

  @doc """
  Returns the list of addresses.

  ## Examples

      iex> list_addresses()
      [%Address{}, ...]

  """
  def list_addresses do
    Repo.all(Address)
  end

  @doc """
  Gets a single address.

  Raises `Ecto.NoResultsError` if the Address does not exist.

  ## Examples

      iex> get_address!(123)
      %Address{}

      iex> get_address!(456)
      ** (Ecto.NoResultsError)

  """
  def get_address!(id), do: Repo.get!(Address, id)

  @doc """
  Gets a single address by its hash and send it as a map

  ## Examples

      iex> get_address_by_hash_for_view(123)
      %{}

      iex> get_address_by_hash_for_view(456)
      nil

  """
  def get_address_by_hash_for_view(hash) do
   his_query = from h in History,
     order_by: [desc: h.block_height],
     select: %{
       txid: h.txid
     }

   claim_query = from h in Claim,
     select: %{
       txids: h.txids
     }
   query = from e in Address,
     where: e.address == ^hash,
     preload: [histories: ^his_query],
     preload: [claimed: ^claim_query],
     select: e #%{:address => e.address, :tx_ids => e.histories, :balance => e.balance, :claimed => e.claimed}
   Repo.all(query)
   |> List.first
  end


  @doc """
  Gets a single address by its hash and send it as a map

  ## Examples

      iex> get_address_by_hash(123)
      %{}

      iex> get_address_by_hash(456)
      nil

  """
  def get_address_by_hash(hash) do

   query = from e in Address,
     where: e.address == ^hash,
     select: e

   Repo.all(query)
   |> List.first
  end

  @doc """
  Creates a address.

  ## Examples

      iex> create_address(%{field: value})
      %Address{}

      iex> create_address(%{field: bad_value})
      no_return

  """
  def create_address(attrs \\ %{}) do
    %Address{}
    |> Address.changeset(attrs)
    |> Repo.insert!()
  end

  @doc """
  Updates a address.

  ## Examples

      iex> update_address(address, %{field: new_value})
      %Address{}

      iex> update_address(address, %{field: bad_value})
      no_return

  """
  def update_address(%Address{} = address, attrs) do
    address
    |> Address.update_changeset(attrs)
    |> Repo.update!()
  end

  #updates all addresses in the transactions with their respective changes/inserts
  def update_multiple_addresses(list) do
    list
    |> Enum.map(fn {address, attrs} -> verify_if_claim(address, attrs) end)
    |> create_multi
    |> Repo.transaction
    |> check_repo_transaction_results()
  end

  #verify if there was claim operations for the address
  def verify_if_claim(address, %{:claimed => claim} = attrs) do
    {address, change_claim(%Claim{}, address, claim), change_history(%History{}, address,  attrs.tx_ids), change_address(address, attrs)}
  end
  def verify_if_claim(address, attrs)do
    {address, nil, change_history(%History{}, address,  attrs.tx_ids), change_address(address, attrs)}
  end

  #creates new Ecto.Multi sequence for single DB transaction
  def create_multi(changesets) do
    Enum.reduce(changesets, Multi.new, fn (tuple, acc) -> insert_updates(tuple, acc) end)
  end

  #Insert address updates in the Ecto.Multi
  def insert_updates({address,claim_changeset, history_changeset, address_changeset}, acc) do
      name = String.to_atom(address.address)
      name1 = String.to_atom("#{address.address}_history")
      name2 = String.to_atom("#{address.address}_claim")

      acc
      |> Multi.update(name, address_changeset, [])
      |> Multi.insert(name1, history_changeset, [])
      |> add_claim_if_claim(name2, claim_changeset)
  end

  #Insert new claim if there was claim operations
  def add_claim_if_claim(multi, _name, nil) do
    multi
  end
  def add_claim_if_claim(multi, name, changeset) do
    multi
    |> Multi.insert(name, changeset, [])
  end

  #verify if DB transaction was sucessfull
  def check_repo_transaction_results({:ok, _any}) do
    {:ok, "all operations were succesfull"}
  end
  def check_repo_transaction_results({:error, error}) do
    IO.inspect(error)
    raise "error updating addresses"
  end


  @doc """
  Deletes a Address.

  ## Examples

      iex> delete_address(address)
      {:ok, %Address{}}

      iex> delete_address(address)
      {:error, %Ecto.Changeset{}}

  """
  def delete_address(%Address{} = address) do
    Repo.delete!(address)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking address changes.

  ## Examples

      iex> change_address(address)
      %Ecto.Changeset{source: %Address{}}

  """
  def change_address(%Address{} = address, attrs) do
    Address.update_changeset(address, attrs)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking address history changes.

  ## Examples

      iex> change_history(history)
      %Ecto.Changeset{source: %History{}}

  """
  def change_history(%History{} = history, address, attrs) do
    History.changeset(history, address, attrs)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking address claim changes.

  ## Examples

      iex> change_claim(claim)
      %Ecto.Changeset{source: %History{}}

  """
  def change_claim(%Claim{} = claim, address, attrs) do
    Claim.changeset(claim, address, attrs)
  end

  @doc """
  Check if address exist in database

  ## Examples

      iex> check_if_exist(existing_address})
      true

      iex> check_if_exist(new_address})
      false

  """
  def check_if_exist(address) do
    query = from e in Address,
      where: e.address == ^address,
      select: e.addres

    case Repo.all(query) |> List.first do
      nil ->
        false
      :string ->
        true
    end
  end

  @doc """
  Populates tuples {address_hash, vins} with {%Adddress{}, vins}

  ## Examples

      iex> populate_groups(groups})
      [{%Address{}, _},...]


  """
  def populate_groups(groups, address_list) do
    Enum.map(groups, fn {address, vins} -> {Enum.find(address_list, fn {%{:address => ad}, _attrs} -> ad == address end), vins} end)
  end

  #get all addresses involved in a transaction
  def get_transaction_addresses(vins, vouts, time) do

    lookups = (map_vins(vins) ++ map_vouts(vouts)) |> Enum.uniq

    query =  from e in Address,
     where: e.address in ^lookups,
     select: struct(e, [:id, :address, :balance])

     Repo.all(query)
     |> fetch_missing(lookups, time)
     |> gen_attrs()
  end

  #helper to filter nil cases
  def map_vins(nil) do
    []
  end
  def map_vins(vins) do
    Enum.map(vins, fn %{:address_hash => address} -> address end)
  end

  #helper to filter nil cases
  def map_claims(nil) do
    []
  end
  def map_claims(claims) do
    Enum.map(claims, fn %{:address_hash => address} -> address end)
  end

  #helper to filter nil cases
  def map_vouts(nil) do
    []
  end
  def map_vouts(vouts) do
    #not in db, so still uses string keys
    Enum.map(vouts, fn %{"address" => address} -> address end)
  end

  #create missing addresses
  def fetch_missing(address_list, lookups, time) do
    (lookups -- Enum.map(address_list, fn %{:address => address} -> address end))
    |> Enum.map(fn address -> create_address(%{"address" => address, "time" => time}) end)
    |> Enum.concat(address_list)
  end



  #Update vins and claims into addresses
  def update_all_addresses(address_list,[], nil, _vouts, _txid, _index, _time) do
    address_list
  end
  def update_all_addresses(address_list,[], claims, vouts, _txid, index, time) do
    address_list
    |> separate_txids_and_insert_claims(claims, vouts, index, time)
  end
  def update_all_addresses(address_list, vins, nil, _vouts, txid, index, time) do
    address_list
    |> group_vins_by_address_and_update(vins, txid, index, time)
  end
  def update_all_addresses(address_list, vins, claims, vouts, txid, index, time) do
    address_list
    |> group_vins_by_address_and_update(vins, txid, index, time)
    |> separate_txids_and_insert_claims(claims, vouts, index, time)
  end

  #generate {address, address_updates} tuples for following operations
  def gen_attrs(address_list) do
    address_list
    |> Enum.map(fn address -> { address, %{}} end)
  end

  #separate vins by address hash, insert vins and update the address
  def group_vins_by_address_and_update(address_list, vins, txid, index, time) do
    updates = Enum.group_by(vins, fn %{:address_hash => address} -> address end)
    |> Map.to_list()
    |> populate_groups(address_list)
    |> Enum.map(fn {address, vins} -> insert_vins_in_address(address, vins, txid, index, time) end)


    Enum.map(address_list, fn {address, attrs} -> substitute_if_updated(address, attrs, updates) end)
  end

  #separate claimed transactions and insert in the claiming addresses
  def separate_txids_and_insert_claims(address_list, claims, vouts, index, time) do
    updates = Stream.map(claims, fn %{:txid => txid } -> String.slice(to_string(txid), -64..-1) end)
    |> Stream.uniq()
    |> Enum.to_list
    |> insert_claim_in_addresses(vouts, address_list, index, time)

    Enum.map(address_list, fn {address, attrs} -> substitute_if_updated(address, attrs, updates) end)
  end

  #helper to substitute main address list with updated addresses tuples
  def substitute_if_updated(%{:address => address_hash} = address, attrs, updates) do
    index = Enum.find_index(updates, fn {%{:address => ad} , _attrs} -> ad == address_hash end)
    case index do
      nil ->
        {address, attrs}
      _ ->
        Enum.at(updates, index)
    end
  end


  #helpers to check if there are attrs updates already
  def check_if_attrs_balance_exists(%{:balance => balance}) do
    balance
  end
  def check_if_attrs_balance_exists(_attrs) do
    false
  end
  def check_if_attrs_txids_exists(%{:tx_ids => tx_ids}) do
    tx_ids
  end
  def check_if_attrs_txids_exists(_attrs) do
    false
  end
  def check_if_attrs_claimed_exists(%{:claimed => claimed}) do
    claimed
  end
  def check_if_attrs_claimed_exists(_attrs) do
    false
  end


  #insert vouts into address balance
  def insert_vouts_in_address(%{:txid => txid, :block_height => index, :time => time} = transaction, vouts) do
    %{"address" => {address , attrs }} = List.first(vouts)
    new_attrs = Map.merge( attrs, %{:balance => check_if_attrs_balance_exists(attrs) || address.balance , :tx_ids => check_if_attrs_txids_exists(attrs) || %{}})
      |> add_vouts(vouts, transaction)
      |> add_tx_id(txid, index, time)
    {address, new_attrs}
  end

  #insert vins into address balance
  def insert_vins_in_address({address, attrs}, vins, txid, index, time) do
    new_attrs = Map.merge(attrs, %{:balance => check_if_attrs_balance_exists(attrs) || address.balance, :tx_ids => check_if_attrs_txids_exists(attrs) || %{}})
    |> add_vins(vins)
    |> add_tx_id(txid, index, time)
    {address, new_attrs}
  end

  #add multiple vins
  def add_vins(attrs, vins) do
    Enum.reduce(vins, attrs, fn (vin, acc) -> add_vin(acc, vin) end)
  end


  #add multiple vouts
  def add_vouts(attrs, vouts, transaction) do
    Enum.reduce(vouts, attrs, fn (vout, acc) ->
      Vouts.create_vout(transaction, vout)
      |> add_vout(acc)
    end)
  end

  #get addresses and route for adding claims
  def insert_claim_in_addresses(transactions, vouts, address_list, index, time) do
    Enum.map(vouts, fn %{"address" => hash, "value" => value, "asset" => asset} ->
      insert_claim_in_address(Enum.find(address_list, fn {%{:address => address}, _attrs} -> address == hash end) , transactions, value, String.slice(to_string(asset), -64..-1), index, time)
    end)
  end

  #insert claimed transactions and update address balance
  def insert_claim_in_address({address, attrs}, transactions, value, asset, index, time) do
    new_attrs = Map.merge(attrs, %{:claimed => check_if_attrs_claimed_exists(attrs) || %{} })
    |> add_claim(transactions, value, asset, index, time)

    {address, new_attrs}
  end

  #add a single vout into adress
  def add_vout(%{:value => value} = vout, %{:balance => balance} = address) do
    current_amount = balance[vout.asset]["amount"] || 0
    new_balance = %{"asset" => vout.asset, "amount" => current_amount + value}
    %{address | balance: Map.put(address.balance || %{}, vout.asset, new_balance)}
  end

  #add a single vin into adress
  def add_vin(%{:balance => balance} = attrs, vin) do
    current_amount = balance[vin.asset]["amount"]
    new_balance = %{"asset" => vin.asset, "amount" => current_amount - vin.value}
    %{attrs | balance: Map.put(attrs.balance || %{}, vin.asset, new_balance)}
  end

  #add a transaction id into address
  def add_tx_id(address, txid, index, time) do
      new_tx = %{:txid => txid, :balance => address.balance, :block_height => index, :time => time}
      %{address | tx_ids: new_tx}
  end

  #add a single claim into address
  def add_claim(address, transactions, amount, asset, index, time) do
    new_claim = %{:txids => transactions, :amount => amount, :asset => asset, :block_height => index, :time => time}
    %{address | claimed: new_claim}
  end

end
