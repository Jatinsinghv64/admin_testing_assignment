APP_PID=$(pgrep -f "flutter run")
if [ -n "$APP_PID" ]; then
    kill -SIGUSR1 $APP_PID
    echo "Reload triggered"
else
    echo "NO_PID"
fi
