# Intentionally inefficient Dockerfile for comparison.
# Builds and runs from the full .NET SDK image.
FROM mcr.microsoft.com/dotnet/sdk:10.0

WORKDIR /src

# Copy the complete source tree before restoring packages.
# Any source change therefore invalidates the restore layer.
COPY . .

RUN dotnet restore UrlShortener.csproj
RUN dotnet publish UrlShortener.csproj -c Release -o /app/publish --no-restore

WORKDIR /app/publish
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080

ENTRYPOINT ["dotnet", "UrlShortener.dll"]
