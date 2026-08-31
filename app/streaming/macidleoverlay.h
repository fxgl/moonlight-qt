#pragma once

#include <memory>

struct SDL_Window;

class MacIdleOverlay
{
public:
    explicit MacIdleOverlay(SDL_Window* window);
    ~MacIdleOverlay();

    void setVisible(bool visible);

private:
    class Impl;
    std::unique_ptr<Impl> m_Impl;
};
