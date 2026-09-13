FROM alpine:3.22.1

ARG SOURCE_URL
ARG VERSION
LABEL org.opencontainers.image.source="$SOURCE_URL"
LABEL org.opencontainers.image.title="Cloudreve Android APK bundle"
LABEL org.opencontainers.image.description="Generic Cloudreve Android APKs without a preset server"
LABEL org.opencontainers.image.version="$VERSION"

COPY dist/ /opt/cloudreve-android/
WORKDIR /opt/cloudreve-android
CMD ["sh"]
