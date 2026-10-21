# picsee

picsee is a macOS image viewer that browses images where they already are on disk, inside the sandbox. This glossary fixes the words for what the user can reach and how it is remembered.

## Language

### Access

**Access Root**（授权根）:
A folder the user granted through the system open panel, which picsee keeps a bookmark for across relaunches.
_Avoid_: authorized directory, location, 授权目录 (as a noun for the stored grant)

**File Grant**（单文件授权）:
Access to one file, given by opening it from Finder or dragging it in, that lasts only for the current session.
_Avoid_: calling it an Access Root, file bookmark

### Library

**Library**（图库）:
The sidebar's set of Library Folders and the "All Photos" view over them; it references images in place and never imports or copies them.
_Avoid_: catalog, collection, import

**Library Folder**（图库文件夹）:
A folder the user explicitly added to the Library, always lying inside some Access Root.
_Avoid_: source, location

**Recent Item**（最近项）:
A record that a file or folder was recently viewed, which reopens without asking only while it is still inside an Access Root.
_Avoid_: recent grant, history bookmark

### Viewing

**Preview Set**（预览集合）:
The ordered list of images the viewer pages through, fixed when the viewer opens: the whole filtered and sorted folder for a single selection, or only the selected images in grid order for a multi-selection.
_Avoid_: playlist, range, "all images" when only a selection was meant

## Relationships

- An **Access Root** is created only by a user action in the system open panel; a **File Grant** never becomes one by itself.
- A **Library Folder** lies inside exactly one **Access Root**; adding a Library Folder inside an existing Access Root creates no new grant.
- Granting an **Access Root** does not add a **Library Folder**; only the explicit "Add Folder" action does.
- A **Preview Set** never grows after the viewer opens; deleted or unauthorized items drop out of it.
- A **Recent Item** confers no access; reopening one outside every **Access Root** asks the user to grant its folder.

## Example dialogue

> **Dev:** "The user opened `~/Downloads/a.jpg` from Finder and pressed →. Do we show the Downloads folder in the sidebar?"
> **Domain expert:** "They only have a **File Grant**, so → asks them to grant `~/Downloads`. Once they do, it is an **Access Root** and shows under Recent, but it is not a **Library Folder** until they choose Add Folder."
> **Dev:** "And next launch, if they click `a.jpg` in Recent?"
> **Domain expert:** "It opens directly, because it is now inside an **Access Root**. Had they never granted the folder, the **Recent Item** would ask for it, since the **File Grant** ended with the session."

## Flagged ambiguities

- "授权目录" was used for both the stored grant and any folder being browsed: resolved as **Access Root** for the stored grant; a folder merely being browsed is just a folder.
- "图库里的文件夹" and "授权的文件夹" were treated as one thing: resolved as distinct, **Library Folder** ⊂ **Access Root**.
