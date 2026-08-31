FROM dart:stable

WORKDIR /app

COPY backend/pubspec.yaml backend/pubspec.lock ./backend/
RUN cd /app/backend && dart pub get

COPY backend ./backend

WORKDIR /app/backend

EXPOSE 8080

ENV PORT=8080

CMD ["sh", "-c", "dart run bin/server.dart"]