class_name Hero
extends RefCounted
## A persistent named character. Heroes command fleets (a doctrine bonus in
## fleet battles) and lead away teams on missions. While on a mission, injured
## or captured they can't do either, which is the cost of sending them.

const READY := "ready"
const ON_MISSION := "on_mission"
const INJURED := "injured"
const CAPTURED := "captured"
const DEAD := "dead"

var id: String
var name: String
var class_id: String
var owner: String  # faction id
var level := 1
var xp := 0
var traits: Array[String] = []
## slot ("weapon" | "armor" | "gadget") -> item id
var gear: Dictionary = {}
## 0-100: how much the hero trusts the faction's leadership. Choices move it.
var loyalty := 50

var status := READY
## Galaxy turn on which an on-mission or injured hero becomes ready again.
var busy_until := 0
## Fleet this hero commands ("" if none). Kept while on a mission or injured:
## the fleet just loses the doctrine bonus until the hero is back.
var fleet_id := ""
## Planet the hero waits at when not aboard a fleet.
var planet_id := ""


func is_ready() -> bool:
	return status == READY


## Can change gear or posting (not away, hurt, captured or dead).
func can_be_managed() -> bool:
	return status == READY or status == INJURED
