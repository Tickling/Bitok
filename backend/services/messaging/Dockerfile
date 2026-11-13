FROM golang:1.24-alpine AS build
WORKDIR /src
COPY . .
RUN CGO_ENABLED=0 go build -o /out/messaging ./cmd/messaging

FROM gcr.io/distroless/static-debian12
COPY --from=build /out/messaging /messaging
EXPOSE 3005
ENTRYPOINT ["/messaging"]
