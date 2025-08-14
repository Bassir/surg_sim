# Surgeon Simulator - Volumetric Viewer

This project is a web-based 3D volumetric data viewer, specifically designed to visualize medical scan data from a screen-recorded video of axial slices (like an MRI or CT scan). It performs all video processing and rendering entirely on the client-side using WebAssembly and WebGL2.

## Features

-   **Client-Side Processing:** No server backend is required. All processing happens in your browser.
-   **Video to 3D:** Converts a screen recording of medical scan slices into a 3D volume.
-   **WebGL2 Rendering:** Uses Volume Ray Casting for high-quality 3D rendering.
-   **Interactive Viewer:** Allows for rotation, zooming, and slicing through the 3D volume.
-   **Segmentation Tools:** Includes a "Magic Wand" tool to segment and highlight regions of interest.

## How to Run

1.  **Install Dependencies:**
    You need to have [Node.js](https://nodejs.org/) and npm installed. Open a terminal in the project root and run:
    ```bash
    npm install
    ```

2.  **Start the Local Server:**
    To run the application, use the following command:
    ```bash
    npm start
    ```
    This will start a local web server, and you can access the application by opening the URL shown in the terminal (usually `http://127.0.0.1:8080`).

3.  **Open the Application:**
    Navigate to `http://127.0.0.1:8080/web/` in your web browser.

## Architecture

For a detailed explanation of the project's architecture, please see the [Architecture Document](./docs/architecture.md).

## Usage

1.  Once the application is running, you will see a drag-and-drop zone.
2.  Select or drag your screen-recorded video file onto the zone.
3.  A progress bar will show the status of the in-browser video processing. This may take a few moments depending on the video length and your computer's performance.
4.  Once processing is complete, the 3D viewer will appear.
5.  Use the controls to manipulate and inspect the 3D model.

---

*This project is managed using [Task Master](https://github.com/eyaltoledano/claude-task-master) for AI-driven development.*
