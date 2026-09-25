class_name EconomyLedger
extends RefCounted

const ACCOUNT_NAMES := ["player_wallet", "player_table", "opponent_funds", "opponent_table", "pot"]
var balances: Dictionary = {}
var initial_total := 0
var transactions: Dictionary = {}
var transaction_log: Array[Dictionary] = []

func _init(player_wallet: int = 0, player_table: int = 0, opponent_funds: int = 0, opponent_table: int = 0, starting_pot: int = 0) -> void:
	balances = {"player_wallet": player_wallet, "player_table": player_table, "opponent_funds": opponent_funds,
		"opponent_table": opponent_table, "pot": starting_pot}
	for account: String in ACCOUNT_NAMES:
		if not _valid_amount(balances[account]):
			balances[account] = 0
	initial_total = total_chips()

static func _valid_amount(value: Variant) -> bool:
	return value is int and value >= 0

func transfer(transaction_id: String, from_account: String, to_account: String, amount: Variant) -> Dictionary:
	if transaction_id.is_empty():
		return _failure("empty_transaction_id")
	if not _valid_amount(amount):
		return _failure("invalid_amount")
	if not balances.has(from_account) or not balances.has(to_account) or from_account == to_account:
		return _failure("invalid_account")
	var fingerprint := "%s|%s|%d" % [from_account, to_account, amount]
	if transactions.has(transaction_id):
		if transactions[transaction_id] != fingerprint:
			return _failure("transaction_id_collision")
		return {"accepted": true, "duplicate": true, "reason": "already_applied", "balances": balances.duplicate(true)}
	if int(balances[from_account]) < amount:
		return _failure("insufficient_funds")
	balances[from_account] = int(balances[from_account]) - amount
	balances[to_account] = int(balances[to_account]) + amount
	transactions[transaction_id] = fingerprint
	transaction_log.append({"transaction_id": transaction_id, "from": from_account, "to": to_account, "amount": amount})
	assert_invariants()
	return {"accepted": true, "duplicate": false, "reason": "ok", "balances": balances.duplicate(true)}

func total_chips() -> int:
	var total := 0
	for account: String in ACCOUNT_NAMES:
		total += int(balances.get(account, 0))
	return total

func assert_invariants() -> bool:
	for account: String in ACCOUNT_NAMES:
		assert(_valid_amount(balances.get(account, -1)), "negative_or_noninteger_balance:%s" % account)
	assert(total_chips() == initial_total, "chip_conservation_broken")
	return true

func snapshot() -> Dictionary:
	return {"balances": balances.duplicate(true), "initial_total": initial_total, "transactions": transactions.duplicate(true),
		"transaction_log": transaction_log.duplicate(true)}

func _failure(reason: String) -> Dictionary:
	return {"accepted": false, "duplicate": false, "reason": reason, "balances": balances.duplicate(true)}

