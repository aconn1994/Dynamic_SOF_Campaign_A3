### Ambient Elements Overhaul



The purpose is to go a layer deeper with the ambient world.  Right now the world feels more alive than it did before, but I believe there is still plenty of room for more variety.

* Deeper spawn elements on tagged locations

* Cities should feel more urban, villages and remote settlements should feel more rural

* Farms should have farmers and ambient animals

* Medical facilities should have medical staff and vehicles

* Industrial areas should have industrial vehicles and equipment

* Civilian factions/types are map based and mapped to location/structure types for realism.  I think this will require some config work with AI assistance.
* With deeper tagging on buildings, intel can give more accurate tips in the briefings:

  * "HVT and guards have taken over a school"
  * "Guards are staying in nearby houses to the target"
  * "The hostage will be transported through the airport. Altis police runs security for the airport terminal and are on the payroll, expect them to be hostile."
  * "Insurgents have garrisoned themselves at the abandoned police barracks near the target.  Expect a QRF from this location."
* Once deeper tagging is implemented, I want the "populate" functionality to focus on civilians first since alot of modern special operations takes place in civilian populated areas, anything abandoned by civilians and entirely military would probably be a conventional military war.
* Dynamic weather

* Random time of year is picked

* Weather is consistent with real life counterpart at time of year (Altis = Lemnos, Greece)

* Overhaul use of factions.  This is TBD, right now I have them hardcoded as profiles based on mod-set that is loaded.  Probably a better way, will probably be influenced by some of the above features.
* Once civilians and weather are done, I would like to keep the functionality for garrison/guard/patrols/roving, but I would like to change the logic of implementing them.  Right now they feel random, I want them to be a bit more calculated based on influence.

  * Random military garrisons in civilian locations are to be removed, rather I would prefer to create "Observation Posts" for military garrisons/units outside of military locations for establishing presence.  I've found that having a random garrison in a city just goes unnoticed and is just wasting compute resources. OPs would be marked as the map via intel maybe to avoid or gain additional intel in the area.
  * Guard units are TBD, but I'm thinking road checkpoints at entry/exit points of locations, static vehicles etc
  * Patrol units are TBD





##### **Potential Structure Tag Refinement**

I created these categories from looking over the existing structure type function. I will manually fill out the new one to be diligent. I have non-occupiable as a tag per category as well.  Also, I want to find a delicate way to list certain structures in the sub-categories for "sentries" only or something.  Such as "Land\_dp\_bigTank\_old\_F", this would be a great structure for snipers/sentries/guards of a warehouse facility but not suitable for an HVT or hostage to just be standing in the open.



###### Residential



* House Big
* Damaged House Big
* House Small
* Damaged House Small
* Attached Rooms
* Multistory Building
* Estate
* Ruins Big
* Ruins Small
* Castle
* Slums
* Sheds
* Gazebo
* Garages
* Non-Occupiable

###### 

###### Commercial

###### 

* Office building
* Shops
* Damaged Shops
* Hotels
* Schools
* Supermarkets
* Garage Complexes
* Gas Stations
* Non-Occupiable



###### Industrial



* Factories
* Warehouse Big
* Warehouse Small
* Workshops
* Autoshop (Land\_CarService\_F)
* Train Stations
* Lighthouses
* Cranes
* Non-Occupiable

###### 

###### Agricultural



* Barn Large
* Barn Small
* Sawmill
* Windmill
* Non-Occupiable



###### Medical



* Hospitals
* Clinics
* Medical Facilities
* Non-Occupiable

###### 

###### Religious



* Churches (Big)
* Chapels (Small)
* Mausoleum
* Non-Occupiable

###### 

###### Port



* Shipyard Big
* Shipyard Small
* Piers
* Cranes
* Non-Occupiable

###### 

###### Airport



* Terminal
* Hangar
* Non-Occupiable

###### 

###### Law Enforcement



* Police Station
* Barracks
* Non-Occupiable

###### 

