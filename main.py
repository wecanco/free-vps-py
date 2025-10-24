import time

print("Python container is running. Waiting indefinitely...")
try:
    while True:
        time.sleep(3600)  # sleep for an hour, then loop forever
except KeyboardInterrupt:
    print("Exiting...")
