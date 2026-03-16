from datetime import datetime, date

from homeassistant.components.calendar import CalendarEntity, CalendarEvent
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
    async_add_entities([GardenOSCalendar(coordinator)], True)


class GardenOSCalendar(CoordinatorEntity, CalendarEntity):
    _attr_name = "GardenOS"
    _attr_unique_id = "garden_os_calendar"

    def __init__(self, coordinator: GardenOSCoordinator) -> None:
        super().__init__(coordinator)

    @property
    def event(self) -> CalendarEvent | None:
        tasks = self.coordinator.data.get("tasks", [])
        today = date.today().isoformat()
        today_tasks = [t for t in tasks if t.get("due_date") == today]
        if not today_tasks:
            return None
        task = today_tasks[0]
        return CalendarEvent(
            summary=task["title"],
            start=date.today(),
            end=date.today(),
        )

    async def async_get_events(
        self, hass: HomeAssistant, start_date: datetime, end_date: datetime
    ) -> list[CalendarEvent]:
        tasks = self.coordinator.data.get("tasks", [])
        events = []
        for task in tasks:
            due = task.get("due_date")
            if not due:
                continue
            task_date = date.fromisoformat(due)
            if start_date.date() <= task_date <= end_date.date():
                events.append(CalendarEvent(
                    summary=task["title"],
                    start=task_date,
                    end=task_date,
                    description=task.get("notes", ""),
                ))
        return events
