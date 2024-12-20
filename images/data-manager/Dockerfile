### build stage ###
FROM golang:1.23.2-alpine AS builder
COPY data-manager.go .
COPY go.mod .
RUN go build -o app .

### run stage ###
FROM alpine:3.20
COPY --from=builder /go/app ./app
CMD ["./app"]