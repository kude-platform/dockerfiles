### build stage ###
FROM golang:1.14-alpine AS builder
COPY log-collector.go .
RUN go build -o server .

### run stage ###
FROM alpine:3.12
COPY --from=builder /go/server ./server
COPY index.html index.html
CMD ["./server"]