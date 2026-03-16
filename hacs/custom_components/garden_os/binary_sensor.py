from homeassistant.components.binary_sensor import (
    BinarySensorDeviceClass,
    BinarySensorEntity,
)
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
    async_add_entities([
        GardenOSFrostRiskSensor(coordinator),
        GardenOSSuccessionDueSensor(coordinator),
        GardenOSGerminationOverdueSensor(coordinator),
    ], True)


class GardenOSFrostRiskSensor(CoordinatorEntity, BinarySensorEntity):
    _attr_name = "GardenOS Frost Risk"
    _attr_unique_id = "garden_os_frost_risk"
    _attr_device_class = BinarySensorDeviceClass.SAFETY

    def __init__(self, coordinator: GardenOSCoordinator) -> None:
        super().__init__(coordinator)

    @property
    def is_on(self):
        tasks = self.coordinator.data.get("tasks", [])
        return any(
            t.get("task_type") == "check" and "frost" in t.get("title", "").lower()
            for t in tasks
        )


class GardenOSSuccessionDueSensor(CoordinatorEntity, BinarySensorEntity):
    _attr_name = "GardenOS Succession Due"
    _attr_unique_id = "garden_os_succession_due"

    def __init__(self, coordinator: GardenOSCoordinator) -> None:
        super().__init__(coordinator)

    @property
    def is_on(self):
        tasks = self.coordinator.data.get("tasks", [])
        return any(t.get("task_type") == "sow" for t in tasks)


class GardenOSGerminationOverdueSensor(CoordinatorEntity, BinarySensorEntity):
    _attr_name = "GardenOS Germination Overdue"
    _attr_unique_id = "garden_os_germination_overdue"

    def __init__(self, coordinator: GardenOSCoordinator) -> None:
        super().__init__(coordinator)

    @property
    def is_on(self):
        tasks = self.coordinator.data.get("tasks", [])
        return any(
            t.get("task_type") == "check" and "germinating" in t.get("title", "").lower()
            for t in tasks
        )
