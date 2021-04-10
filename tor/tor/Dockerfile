FROM alpine:3
RUN apk add --no-cache tor
COPY --chown=tor:tor ./tmp /app
RUN chmod 700 /app
USER tor
CMD ["tor", "-f" ,"/app/torrc"]
