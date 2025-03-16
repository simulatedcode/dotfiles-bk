#!/bin/bash

battery_level=$(pmset -g batt | grep -Eo '[0-9]+%' | tr -d '%')
battery_status=$(pmset -g batt | grep "AC Power")

if [ "$battery_level" -le 30 ]; then
  color="#dc322f" # Red for low battery
elif [ "$battery_level" -le 60 ]; then
  color="#bc5329" # Yellow for medium battery
else
  color="#001419" # Cyan for high battery
fi

if [[ -z "$battery_status" ]]; then
  echo "#[fg=$color]  $battery_level%"
else
  echo "#[fg=#255ab4]   Charging ($battery_level%)"
fi
