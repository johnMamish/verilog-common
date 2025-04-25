#!/usr/bin/env bash
shopt -s nullglob

for entry in /sys/bus/usb/drivers/ftdi_sio/*:*; do
  name=${entry##*/}          # strip path, yields e.g. "2-1:1.1"
  device=${name%%:*}         # yields "2-1"
  prod="/sys/bus/usb/devices/$device/idProduct"
  vend="/sys/bus/usb/devices/$device/idVendor"
  echo $name
  if [[ -r $prod && -r $vend ]]; then
      if [[ $(<"$prod") == "6014" && $(<"$vend") == "0403" ]]; then
          echo "the command you want to run is"
          echo "echo -n $name | sudo tee /sys/bus/usb/drivers/ftdi_sio/unbind > /dev/null"
      fi
  fi
done
