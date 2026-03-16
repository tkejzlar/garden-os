import logging
from datetime import timedelta
import aiohttp

from homeassistant.core import HomeAssistant
from homeassistant.helpers.update_coordinator import DataUpdateCoordinator

from .const import SCAN_INTERVAL

_LOGGER = logging.getLogger(__name__)


class GardenOSCoordinator(DataUpdateCoordinator):
    def __init__(self, hass: HomeAssistant, url: str) -> None:
        super().__init__(
            hass,
            _LOGGER,
            name="GardenOS",
            update_interval=timedelta(seconds=SCAN_INTERVAL),
        )
        self.api_url = url.rstrip("/")

    async def _async_update_data(self):
        async with aiohttp.ClientSession() as session:
            plants_resp = await session.get(f"{self.api_url}/api/plants")
            plants = await plants_resp.json()

            tasks_resp = await session.get(f"{self.api_url}/api/tasks")
            tasks = await tasks_resp.json()

            beds_resp = await session.get(f"{self.api_url}/api/beds")
            beds = await beds_resp.json()

            return {
                "plants": plants,
                "tasks": tasks,
                "beds": beds,
            }
