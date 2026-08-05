class_name AgentPolicy
extends Resource

enum Authorization {
	ADVISORY,
	ASSISTED,
	DELEGATED,
	AUTONOMOUS,
}

enum Domain {
	TEST,
	INDUSTRIAL,
	BATTLEFIELD,
	ENEMY,
}

@export var agent_id: int = 0
@export var faction_id: int = 0
@export var domain: Domain = Domain.TEST
@export var authorization: Authorization = Authorization.ASSISTED


func allows_explicit_tasks() -> bool:
	return authorization >= Authorization.ASSISTED


func allows_domain_management() -> bool:
	return authorization >= Authorization.DELEGATED


func allows_proactive_tasks() -> bool:
	return authorization >= Authorization.AUTONOMOUS

