#include <stdio.h>
#include <stdint.h>
#include <ctype.h>
#include <stdlib.h>
#include <string.h>

typedef uint8_t bool;
#define true 1
#define false 0

typedef struct
{
    uint8_t BootJumpInstruction[3];
    uint8_t OemIdentifier[8];
    uint16_t BytesPerSector;
    uint8_t SectorsPerCluster;
    uint16_t ReservedSectors;
    uint8_t FatCount;
    uint16_t DirEntryCount;
    uint16_t TotalSectors;
    uint8_t MediaDescriptorType;
    uint16_t SectorsPerFat;
    uint16_t SectorsPerTrack;
    uint16_t Heads;
    uint32_t HiddenSectors;
    uint32_t LargeSectorCount;

    // extended boot record
    uint8_t DriveNumber;
    uint8_t _Reserved;
    uint8_t Signature;
    uint32_t VolumeId;       // serial number, value doesn't matter
    uint8_t VolumeLabel[11]; // 11 bytes, padded with spaces
    uint8_t SystemId[8];

    // ... we don't care about code ...

} __attribute__((packed)) BootSector;

typedef struct
{
    uint8_t Name[11];
    uint8_t Attributes;
    uint8_t _Reserved;
    uint8_t CreatedTimeTenths;
    uint16_t CreatedTime;
    uint16_t CreatedDate;
    uint16_t AccessedDate;
    uint16_t FirstClusterHigh;
    uint16_t ModifiedTime;
    uint16_t ModifiedDate;
    uint16_t FirstClusterLow;
    uint32_t Size;
} __attribute__((packed)) DirectoryEntry;

BootSector global_bs;
uint8_t *global_fat = NULL;
DirectoryEntry *global_root = NULL;
uint32_t global_rootend;

/*
    Read the boot sector from the disk and store it in a global variable `global_bs`.
*/
bool readBootSector(FILE *disk)
{
    return fread(&global_bs, sizeof(global_bs), 1, disk) > 0;
}

/*
    similar to readSector in assembly.
*/
bool readSector(FILE *disk, uint32_t lba, uint32_t count, void *bufferOut)
{
    bool ok = true;
    ok = ok && (fseek(disk, lba * global_bs.BytesPerSector, SEEK_SET) == 0);
    ok = ok && (fread(bufferOut, global_bs.BytesPerSector, count, disk) == count);
    return ok;
}

/*
    read the file location table to `global_fat`.
*/
bool readFat(FILE *disk)
{
    global_fat = (uint8_t *)malloc(global_bs.SectorsPerFat * global_bs.BytesPerSector); // alloc memory for file location table. alloc the size of 1 fat.
    return readSector(disk, global_bs.ReservedSectors, global_bs.SectorsPerFat, global_fat);
}

/*
    Read the root directory from the disk and store it in a global variable `global_root`.
*/
bool readRootDir(FILE *disk)
{
    uint32_t lba = global_bs.ReservedSectors + global_bs.SectorsPerFat * global_bs.FatCount; // after reserved sectors and fat sectors.
    uint32_t size = sizeof(DirectoryEntry) * global_bs.DirEntryCount;
    uint32_t sectors_cnt = (size / global_bs.BytesPerSector); // how many sectors to read
    if (size % global_bs.BytesPerSector > 0)                  // round up
        sectors_cnt++;

    global_rootend = lba + sectors_cnt;
    global_root = (DirectoryEntry *)malloc(sectors_cnt * global_bs.BytesPerSector); // alloc memory for root directory
    return readSector(disk, lba, sectors_cnt, global_root);
}

/*
    Find the file in the root directory
*/
DirectoryEntry *findFile(const char *name)
{
    // for each file in the root
    for (uint32_t i = 0; i < global_bs.DirEntryCount; i++)
    {
        if (memcmp(name, global_root[i].Name, 11) == 0) // compare
            return &global_root[i];
    }

    return NULL;
}

/*
    Read the file from the disk and store it in a buffer.
    Return true if successful, false otherwise.
*/
bool readFile(DirectoryEntry *fileEntry, FILE *disk, uint8_t *outputBuffer)
{
    bool ok = true;
    uint16_t currCluster = fileEntry->FirstClusterLow;

    do
    {
        uint32_t lba = global_rootend /* = data starts */ + (currCluster - 2 /* 2 clusters reserved */) * global_bs.SectorsPerCluster;
        ok = ok && readSector(disk, lba, global_bs.SectorsPerCluster, outputBuffer);
        outputBuffer += global_bs.SectorsPerCluster * global_bs.BytesPerSector;

        uint32_t fatIndex = currCluster * 3 / 2; // 12 bits per entry, 2 entries per 3 bytes

        if (currCluster % 2 == 0)
            currCluster = (*(uint16_t *)(global_fat + fatIndex)) & 0x0FFF;
        else
            currCluster = (*(uint16_t *)(global_fat + fatIndex)) >> 4;

    } while (ok && currCluster < 0xFF8);

    return ok;
}

/*
    MAIN CODE
*/

#define FREE_FAT free(global_fat);
#define FREE_ROOT free(global_root);
#define FREE_ALL FREE_FAT FREE_ROOT

int main(int argc, char **argv)
{
    if (argc < 3)
    {
        printf("Usage: %s <image file> <file to add>\n", argv[0]);
        return -1;
    }

    FILE *disk = fopen(argv[1], "rb");
    if (!disk)
    {
        fprintf(stderr, "Could not open disk image %s\n", argv[1]);
        return -2;
    }

    if (!readBootSector(disk))
    {
        printf("Could not read boot sector\n");
        return -3;
    }

    if (!readFat(disk))
    {
        printf("Could not read FAT\n");
        free(global_fat);
        return -4;
    }

    if (!readRootDir(disk))
    {
        printf("Could not read Root Dir\n");
        free(global_fat);
        free(global_root);
        return -5;
    }

    DirectoryEntry *file = findFile(argv[2]);
    if (!file)
    {
        fprintf(stderr, "Could not find file %s\n", argv[2]);
        free(global_fat);
        free(global_root);
        return -6;
    }

    uint8_t *buffer = (uint8_t *)malloc(file->Size + global_bs.SectorsPerCluster * global_bs.BytesPerSector);
    if (!readFile(file, disk, buffer))
    {
        fprintf(stderr, "Could not read file %s\n", argv[2]);
        free(global_fat);
        free(global_root);
        free(buffer);
        return -7;
    }

    for (uint32_t i = 0; i < file->Size; i++)
    {
        printf("%c", buffer[i]);
    }

    free(global_fat);
    free(global_root);
    free(buffer);

    return 0;
}