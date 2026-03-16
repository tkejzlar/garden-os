from homeassistant.components.sensor import SensorEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.helpers.update_coordinator import CoordinatorEntity

from .const import DOMAIN
from .coordinator import GardenOSCoordinator


async def async_setup_entry(
    hass: HomeAssistant, entry: ConfigEntry, async_add_entities: AddEntitiesCallback
) -> None:
    coordinator: GardenOSCoordinator = hass.data[DOMAIN][entry.entry_id]
    entities = []

    for plant in coordinator.data.get("plants", []):
        entities.append(GardenOSPlantSensor(coordinator, plant))

    async_add_entities(entities, True)


class GardenOSPlantSensor(CoordinatorEntity, SensorEntity):
    def __init__(self, coordinator: GardenOSCoordinator, plant: dict) -> None:
        super().__init__(coordinator)
        self._plant_id = plant["id"]
        self._attr_name = f"GardenOS {plant.get('crop_type', '')} {plant.get('variety_name', '')}"
        self._attr_unique_id = f"garden_os_plant_{plant['id']}"

    @property
    def native_value(self):
        for plant in self.coordinator.data.get("plants", []):
            if plant["id"] == self._plant_id:
                return plant.get("lifecycle_stage", "unknown")
        return "unknown"

    @property
    def extra_state_attributes(self):
        for plant in self.coordinator.data.get("plants", []):
            if plant["id"] == self._plant_id:
                return {
                    "variety_name": plant.get("variety_name"),
                    "crop_type": plant.get("crop_type"),
                    "sow_date": plant.get("sow_date"),
                    "days_in_stage": plant.get("days_in_stage", 0),
                }
        return {}
